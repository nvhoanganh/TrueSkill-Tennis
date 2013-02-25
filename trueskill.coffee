#!/usr/bin/python
# Copyright 2010 Doug Zongker
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###
Implements the player skill estimation algorithm from Herbrich et al.,
"TrueSkill(TM): A Bayesian Skill Rating System".
###
from __future__ import print_function
__author__ = "Doug Zongker <dougz@isotropic.org>"
import sys
if sys.hexversion < 0x02060000
  print("requires Python 2.6 or higher")
  sys.exit(1)
from scipy.stats.distributions import norm as scipy_norm
sqrt = Math.
norm = scipy_norm()
pdf = norm.pdf
cdf = norm.cdf
icdf = norm.ppf    # inverse CDF
# Update rules for approximate marginals for the win and draw cases,
# respectively.
Vwin=(t, e)->
  return pdf(t-e) / cdf(t-e)
Wwin=(t, e)->
  return Vwin(t, e) * (Vwin(t, e) + t - e)
Vdraw=(t, e)->
  return (pdf(-e-t) - pdf(e-t)) / (cdf(e-t) - cdf(-e-t))
Wdraw=(t, e)->
  return pow(Vdraw(t, e) , 2) + ((e-t) * pdf(e-t) + (e+t) * pdf(e+t)) / (cdf(e-t) - cdf(-e-t))
class Gaussian
  ###
  Object representing a gaussian distribution.  Create as:
    new Gaussian({mu=..., sigma=...})
      or
    new Gaussian({pi=..., tau=...})
      or
    new Gaussian()    # gives 0 mean, infinite sigma
  ###
  constructor:(parms={})->
    if "pi" in parms
      @pi = parms["pi"]
      @tau = parms["tau"]
    else if "mu" in parms
      @pi = pow(parms["sigma"] , -2)
      @tau = @pi * parms["mu"]
    else
      @pi = 0
      @tau = 0
  repr:()->
    return "N(pi={0.pi},tau={0.tau})".format(this)
  toString:()->
    if @pi == 0.0
      return "N(mu=0,sigma=inf)"
    else
      sigma = sqrt(1/@pi)
      mu = @tau / @pi
      return "N(mu={0:.3f},sigma={1:.3f})".format(mu, sigma)
  MuSigma:()->
    ### Return the value of this object as a (mu, sigma) tuple. ###
    if @pi == 0.0
      return 0, float("inf")
    else
      return @tau / @pi, sqrt(1/@pi)
  mul:(other)->
    return new Gaussian({"pi":@pi+other.pi, "tau":@tau+other.tau})
  div:(other)->
    return new Gaussian({"pi":@pi-other.pi, "tau":@tau-other.tau})
class Variable
  ### A variable node in the factor graph. ###
  constructor:()->
    @value = new Gaussian()
    @factors = {}
  AttachFactor:(factor)->
    @factors[factor] = new Gaussian()
  UpdateMessage:(factor, message)->
    old_message = @factors[factor]
    @value = @value.div(old_message).mul(message)
    @factors[factor] = message
  UpdateValue:(factor, value)->
    old_message = @factors[factor]
    @factors[factor] = value.mul(old_message).div(@value)
    @value = value
  GetMessage:(factor)->
    return @factors[factor]
class Factor
  ### Base class for a factor node in the factor graph. ###
  constructor:(variables)->
    @variables = variables
    for v in variables
      v.AttachFactor(this)
# The following Factor classes implement the five update equations
# from Table 1 of the Herbrich et al. paper.
class PriorFactor extends Factor
  ### Connects to a single variable, pushing a fixed (Gaussian) value
  to that variable. ###
  constructor:(variable, param)->
    super([variable])
    @param = param
  Start:()->
    @variables[0].UpdateValue(this, @param)
class LikelihoodFactor extends Factor
  ### Connects two variables, the value of one being the mean of the
  message sent to the other. ###
  constructor:(mean_variable, value_variable, variance)->
    super([mean_variable, value_variable])
    @mean = mean_variable
    @value = value_variable
    @variance = variance
  UpdateValue:()->
    ### Update the value after a change in the mean (going "down" in
    the TrueSkill factor graph. ###
    y = @mean.value
    fy = @mean.GetMessage(this)
    a = 1.0 / (1.0 + @variance * (y.pi - fy.pi))
    @value.UpdateMessage(this, new Gaussian({"pi":a*(y.pi - fy.pi), "tau":a*(y.tau - fy.tau)}))
  UpdateMean:()->
    ### Update the mean after a change in the value (going "up" in
    the TrueSkill factor graph. ###
    # Note this is the same as UpdateValue, with @mean and
    # @value interchanged.
    x = @value.value
    fx = @value.GetMessage(this)
    a = 1.0 / (1.0 + @variance * (x.pi - fx.pi))
    @mean.UpdateMessage(this, new Gaussian({"pi":a*(x.pi - fx.pi),"tau":a*(x.tau - fx.tau)}))
class SumFactor extends Factor
  ### A factor that connects a sum variable with 1 or more terms,
  which are summed after being multiplied by fixed (real)
  coefficients. ###
  constructor:(sum_variable, terms_variables, coeffs)->
    assert len(terms_variables) == len(coeffs)
    @sum = sum_variable
    @terms = terms_variables
    @coeffs = coeffs
    super([sum_variable] + terms_variables)
  _InternalUpdate:(var, y, fy, a)->
    new_pi = 1.0 / (sum(pow(a[j],2) / (y[j].pi - fy[j].pi) for j in range(len(a))))
    new_tau = new_pi * sum(a[j] *
                           (y[j].tau - fy[j].tau) / (y[j].pi - fy[j].pi)
                           for j in range(len(a)))
    var.UpdateMessage(this, new Gaussian({"pi":new_pi, "tau":new_tau}))
  UpdateSum:()->
    ### Update the sum value ("down" in the factor graph). ###
    y = [t.value for t in @terms]
    fy = [t.GetMessage(this) for t in @terms]
    a = @coeffs
    @_InternalUpdate(@sum, y, fy, a)
  UpdateTerm:(index)->
    ### Update one of the term values ("up" in the factor graph). ###
    # Swap the coefficients around to make the term we want to update
    # be the 'sum' of the other terms and the factor's sum, eg.,
    # change:
    #
    #    x = y_1 + y_2 + y_3
    #
    # to
    #
    #    y_2 = x - y_1 - y_3
    #
    # then use the same update equation as for UpdateSum.
    b = @coeffs
    a = [-b[i] / b[index] for i in range(len(b)) if i != index]
    a.insert(index, 1.0 / b[index])
    v = @terms.slice(0)
    v[index] = @sum
    y = [i.value for i in v]
    fy = [i.GetMessage(this) for i in v]
    @_InternalUpdate(@terms[index], y, fy, a)
class TruncateFactor extends Factor
  ### A factor for (approximately) truncating the team difference
  distribution based on a win or a draw (the choice of which is
  determined by the functions you pass as V and W). ###
  constructor:(variable, V, W, epsilon)->
    super([variable])
    @var = variable
    @V = V
    @W = W
    @epsilon = epsilon
  Update:()->
    x = @var.value
    fx = @var.GetMessage(this)
    c = x.pi - fx.pi
    d = x.tau - fx.tau
    sqrt_c = sqrt(c)
    args = (d / sqrt_c, @epsilon * sqrt_c)
    V = @V(*args)
    W = @W(*args)
    new_val = new Gaussian({"pi":c / (1.0 - W), "tau":(d + sqrt_c * V) / (1.0 - W)})
    @var.UpdateValue(this, new_val)
DrawProbability=(epsilon, beta, total_players=2)->
  ### Compute the draw probability given the draw margin (epsilon). ###
  return 2 * cdf(epsilon / (sqrt(total_players) * beta)) - 1
DrawMargin=(p, beta, total_players=2)->
  ### Compute the draw margin (epsilon) given the draw probability. ###
  return icdf((p+1.0)/2) * sqrt(total_players) * beta
INITIAL_MU = 25.0
INITIAL_SIGMA = INITIAL_MU / 3.0
def SetParameters(beta=null, epsilon=null, draw_probability=null,
                  gamma=null):
  ###
  Sets three global parameters used in the TrueSkill algorithm.
  beta is a measure of how random the game is.  You can think of it as
  the difference in skill (mean) needed for the better player to have
  an ~80% chance of winning.  A high value means the game is more
  random (I need to be *much* better than you to consistently overcome
  the randomness of the game and beat you 80% of the time); a low
  value is less random (a slight edge in skill is enough to win
  consistently).  The default value of beta is half of INITIAL_SIGMA
  (the value suggested by the Herbrich et al. paper).
  epsilon is a measure of how common draws are.  Instead of specifying
  epsilon directly you can pass draw_probability instead (a number
  from 0 to 1, saying what fraction of games end in draws), and
  epsilon will be determined from that.  The default epsilon
  corresponds to a draw probability of 0.1 (10%).  (You should pass a
  value for either epsilon or draw_probability, not both.)
  gamma is a small amount by which a player's uncertainty (sigma) is
  increased prior to the start of each game.  This allows us to
  account for skills that vary over time; the effect of old games
  on the estimate will slowly disappear unless reinforced by evidence
  from new games.
  ###
  global BETA, EPSILON, GAMMA
  if beta is null
    BETA = INITIAL_SIGMA / 2.0
  else
    BETA = beta
  if epsilon is null
    if draw_probability is null
      draw_probability = 0.10
    EPSILON = DrawMargin(draw_probability, BETA)
  else
    EPSILON = epsilon
  if gamma is null
    GAMMA = INITIAL_SIGMA / 100.0
  else
    GAMMA = gamma
SetParameters()
AdjustPlayers=(players)->
  ###
  Adjust the skills of a list of players.
  'players' is a list of player objects, for all the players who
  participated in a single game.  A 'player object' is any object with
  a "skill" attribute (a (mu, sigma) tuple) and a "rank" attribute.
  Lower ranks are better; the lowest rank is the overall winner of the
  game.  Equal ranks mean that the two players drew.
  This function updates all the "skill" attributes of the player
  objects to reflect the outcome of the game.  The input list is not
  altered.
  ###
  players = players.slice(0)
  # Sort players by rank, the factor graph will connect adjacent team
  # performance variables.
  players.sort(key=lambda p: p.rank)
  # Create all the variable nodes in the graph.  "Teams" are each a
  # single player; there's a one-to-one correspondence between players
  # and teams.  (It would be straightforward to make multiplayer
  # teams, but it's not needed for my current purposes.)
  ss = [new Variable() for p in players]
  ps = [new Variable() for p in players]
  ts = [new Variable() for p in players]
  ds = [new Variable() for p in players.slice(0,-1)]
  # Create each layer of factor nodes.  At the top we have priors
  # initialized to the player's current skill estimate.
  skill = [new PriorFactor(s, new Gaussian({"mu":pl.skill[0], "sigma":pl.skill[1] + GAMMA}))
           for (s, pl) in zip(ss, players)]
  skill_to_perf = [new LikelihoodFactor(s, p, pow(BETA,2)) for (s, p) in zip(ss, ps)]
  perf_to_team = [new SumFactor(t, [p], [1]) for (p, t) in zip(ps, ts)]
  team_diff = [new SumFactor(d, [t1, t2], [+1, -1]) for (d, t1, t2) in zip(ds, ts.slice(0,-1), ts.slice(1))]
  # At the bottom we connect adjacent teams with a 'win' or 'draw'
  # factor, as determined by the rank values.
  trunc = [new TruncateFactor(d,
                          Vdraw if pl1.rank == pl2.rank else Vwin,
                          Wdraw if pl1.rank == pl2.rank else Wwin,
                          EPSILON)
           for (d, pl1, pl2) in zip(ds, players.slice(0,-1), players.slice(1))]
  # Start evaluating the graph by pushing messages 'down' from the
  # priors.
  for f in skill
    f.Start()
  for f in skill_to_perf
    f.UpdateValue()
  for f in perf_to_team
    f.UpdateSum()
  # Because the truncation factors are approximate, we iterate,
  # adjusting the team performance (t) and team difference (d)
  # variables until they converge.  In practice this seems to happen
  # very quickly, so I just do a fixed number of iterations.
  #
  # This order of evaluation is given by the numbered arrows in Figure
  # 1 of the Herbrich paper.
  for i in range(5)
    for f in team_diff
      f.UpdateSum()             # arrows (1) and (4)
    for f in trunc
      f.Update()                # arrows (2) and (5)
    for f in team_diff
      f.UpdateTerm(0)           # arrows (3) and (6)
      f.UpdateTerm(1)
  # Now we push messages back up the graph, from the teams back to the
  # player skills.
  for f in perf_to_team
    f.UpdateTerm(0)
  for f in skill_to_perf
    f.UpdateMean()
  # Finally, the players' new skills are the new values of the s
  # variables.
  for s, pl in zip(ss, players)
    pl.skill = s.value.MuSigma()
__all__ = ["AdjustPlayers", "SetParameters", "INITIAL_MU", "INITIAL_SIGMA"]