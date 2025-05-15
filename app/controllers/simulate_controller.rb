class SimulateController < ApplicationController
  def block
    start = Time.now
    sleep_time = params[:sleep].to_f || 10
    sleep sleep_time

    render json: { type: "blocked", time: (Time.now - start).to_s, sleep_time: sleep_time }
  end

  def non_block
    start = Time.now
    render json: { type: "non_block", time: (Time.now - start).to_s }
  end

end
