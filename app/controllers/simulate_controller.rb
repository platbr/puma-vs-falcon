class SimulateController < ApplicationController
  def block
    start = Time.now
    fiber = Fiber.new do
      puts "Start"
      sleep 10
      puts "End after 10 seconds"
    end
    fiber.resume

    render json: { type: "blocked", time: (Time.now - start).to_s }
  end

  def non_block
    start = Time.now
    render json: { type: "non_block", time: (Time.now - start).to_s }
  end
end
