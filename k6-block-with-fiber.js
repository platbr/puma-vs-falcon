import http from 'k6/http';
import { group } from 'k6'
export const options = {
  executor: 'ramping-vus',
  startVUs: 10,
  stages: [
    { duration: '60s', target: 10 }
  ],
  gracefulRampDown: '60s'
};

export default function () {
  group('sleep 5 seconds - with fiber', function () {
    http.get('http://localhost:3000/simulate/block?sleep=5');
  });
}
