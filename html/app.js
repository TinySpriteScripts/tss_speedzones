(function () {
  'use strict';
  var timer = document.getElementById('timer');
  var speed = document.getElementById('speed');
  var goal = document.getElementById('goal');
  var progress = document.getElementById('progress');
  var results = document.getElementById('results');

  function hideAll() { timer.classList.add('hidden'); results.classList.add('hidden'); }
  function mph(value) { return Math.round(Number(value) || 0) + ' MPH'; }
  function rewardRow(label, value) {
    return '<div class="ev-results-reward-row"><span class="ev-results-reward-label">' + label + '</span><span class="ev-results-reward-value">' + value + '</span></div>';
  }

  window.addEventListener('message', function (event) {
    var data = event.data || {};
    if (data.type === 'timerStart') {
      results.classList.add('hidden');
      timer.classList.remove('hidden');
      speed.textContent = '0 MPH';
      goal.textContent = 'TARGET ' + mph(data.target);
      progress.textContent = 'CHECKPOINT ' + data.current + ' / ' + data.total;
    } else if (data.type === 'timerTick') {
      speed.textContent = mph(data.average);
      goal.textContent = 'TARGET ' + mph(data.target);
      goal.className = 'ev-timer-goal ' + (data.average >= data.target ? 'is-ahead' : 'is-behind');
    } else if (data.type === 'progress') {
      progress.textContent = 'CHECKPOINT ' + data.current + ' / ' + data.total;
    } else if (data.type === 'timerStop') {
      timer.classList.add('hidden');
    } else if (data.type === 'results') {
      timer.classList.add('hidden');
      results.classList.remove('hidden');
      document.getElementById('name').textContent = data.name || '';
      document.getElementById('average').textContent = mph(data.average);
      document.getElementById('target').textContent = 'TARGET ' + mph(data.target);
      var verdict = document.getElementById('verdict');
      verdict.textContent = data.passed ? (data.newlyCompleted ? 'ZONE CLEARED' : 'TARGET BEATEN') : 'TARGET MISSED';
      verdict.className = 'ev-results-verdict ' + (data.passed ? 'is-pass' : 'is-fail');
      document.getElementById('kicker').textContent = data.newlyCompleted ? 'SPEED ZONE CLEARED' : 'SPEED ZONE COMPLETE';
      var reward = data.reward;
      var rows = '';
      if (reward) {
        if (reward.cash && reward.cash.amount) rows += rewardRow('CASH', '+$' + reward.cash.amount);
        if (reward.player && reward.player.xpGained) rows += rewardRow('PLAYER XP', '+' + reward.player.xpGained + ' XP');
        if (reward.vehicle && reward.vehicle.xpGained) rows += rewardRow('VEHICLE XP', '+' + reward.vehicle.xpGained + ' XP');
      }
      document.getElementById('rewardRows').innerHTML = rows;
      document.getElementById('rewards').classList.toggle('hidden', !rows);
    } else if (data.type === 'hide') {
      hideAll();
    }
  });
})();
