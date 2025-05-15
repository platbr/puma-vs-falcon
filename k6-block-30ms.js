import http from 'k6/http';
import {check,group } from 'k6'
export const options = {
  vus: 30,
  duration: '30s',
};

export default function () {
  group('sleep 30 ms', function () {
    check(http.get('http://localhost:3000/simulate/block?sleep=0.03'),{
      'response code was 200': (res) => res.status == 200,
    });
  });
}
