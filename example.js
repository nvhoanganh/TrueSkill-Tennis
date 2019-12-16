var _ = require('lodash');
var trueskill = require('./trueskill');

const scoreToString = p => ({
  name: p.name,
  played: p.win + p.lost,
  win: p.win,
  lost: p.lost,
  winPercentage: Math.round((p.win / (p.win + p.lost)) * 100 * 100) / 100,
  score: p.skill[0] - 3 * p.skill[1],
  prizeMoney_$: (p.win - p.lost) * 5,
  mu: p.skill[0],
  sigm: p.skill[1]
});

const getSorted = a => _.sortBy(a.map(scoreToString), ['score']).reverse();
// const getSorted = a => a.map(scoreToString);

const numberOfGames = 267;
const mu = 25;
const sigma = 3;
const initialScore = [mu, mu / sigma];
const playerNames = ['h.a', 'tx', 'cuong', 'phuc', 'aTuan', 'aThang', 'hoang', 'tu', 'viet'];

let players = playerNames.map(p => ({
  name: p,
  win: 0,
  lost: 0,
  skill: [...initialScore]
}));

const runResult = [];
for (let run = 0; run < 2; run++) {
  players = playerNames.map(p => ({
    name: p,
    win: 0,

    lost: 0,
    skill: [...initialScore]
  }));
  console.log('-------------------------------------');
  console.log(`run #${run + 1} - ${numberOfGames} samples,mu = ${mu}, sigma = ${sigma}`);
  for (let index = 0; index < numberOfGames; index++) {
    const winners = _.sampleSize(players, 2);
    const others = players.filter(p => winners.filter(x => x.name === p.name).length === 0);
    const losers = _.sampleSize(others, 2);
    console.log('-------------------------------------');
    console.log(
      `run# ${run + 1} - match #${index + 1} > Winners: ${winners.map(x => x.name).join(',')}, Losers: ${losers
        .map(x => x.name)
        .join(',')}`
    );

    winners.forEach(p => {
      p.rank = 1;
      p.win = p.win + 1;
    });

    losers.forEach(p => {
      p.rank = 2;
      p.lost = p.lost + 1;
    });

    trueskill.AdjustPlayers([...winners, ...losers]);

    console.log(`run# ${run + 1} - Leaderboard after ${index + 1} matches:`);
    console.table(getSorted(players));
  }
  runResult.push(getSorted(players));
}

console.log('=======================================');
console.log('all Runs result');
runResult.forEach((r, i) => {
  console.log('Run #' + (i + 1));
  console.table(r);
});
console.log('=======================================');
