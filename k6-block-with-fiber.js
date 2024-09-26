import http from 'k6/http';
import {check,group } from 'k6'
export const options = {
  executor: 'constant-vus',
  vus: 30,
  duration: '60s',
};

export default function () {
  group('sleep 5 seconds - with fiber', function () {
    check(http.get('http://localhost:3000/simulate/block?sleep=5'),{
      'response code was 200': (res) => res.status == 200,
    });
  });
}
