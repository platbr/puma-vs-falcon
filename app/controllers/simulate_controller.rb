class SimulateController < ApplicationController
  def block
    start = Time.now
    sleep_time = params[:sleep].to_i || 10
    fiber = Fiber.new do
      sleep sleep_time
    end
    fiber.resume

    render json: { type: "blocked", time: (Time.now - start).to_s, sleep_time: sleep_time }
  end

  def non_block
    start = Time.now
    render json: { type: "non_block", time: (Time.now - start).to_s }
  end

  def block_no_fiber
    start = Time.now
    sleep_time = params[:sleep].to_i || 10
    sleep sleep_time

    render json: { type: "block_no_fiber", time: (Time.now - start).to_s, sleep_time: sleep_time}
  end
end
