#!/bin/bash
echo "Running 3 blocking requests.."
sleep 1
curl http://localhost:3000/simulate/block &
curl http://localhost:3000/simulate/block &
curl http://localhost:3000/simulate/block &
sleep 1
echo "Running 1 non-blocking request.."
curl http://localhost:3000/simulate/non-block