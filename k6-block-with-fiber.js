import http from 'k6/http';
import {check,group } from 'k6'
export const options = {
  executor: 'ramping-vus',
  startVUs: 30,
  stages: [
    { duration: '60s', target: 30 }
  ],
  gracefulRampDown: '600s'
};

export default function () {
  group('sleep 5 seconds - with fiber', function () {
    check(http.get('http://localhost:3000/simulate/block?sleep=5'),{
      'response code was 200': (res) => res.status == 200,
    });
  });
}
