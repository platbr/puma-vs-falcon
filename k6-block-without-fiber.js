import http from 'k6/http';
import { group } from 'k6'
export const options = {
  executor: 'ramping-vus',
  startVUs: 30,
  stages: [
    { duration: '60s', target: 30 }
  ],
  gracefulRampDown: '60s'
};

export default function () {
  group('sleep 5 seconds - without fiber', function () {
    http.get('http://localhost:3000/simulate/block_no_fiber?sleep=5');
  });
}
