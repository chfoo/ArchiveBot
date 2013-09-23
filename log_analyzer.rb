require File.expand_path('../log_update_listener', __FILE__)
require File.expand_path('../job', __FILE__)

class LogAnalyzer < LogUpdateListener
  def initialize(redis_url, update_channel)
    @jobs = {}

    super
  end

  def on_shutdown
    @jobs.clear
  end

  def on_receive(ident)
    if !@jobs.has_key?(ident)
      @jobs[ident] = ::Job.from_ident(ident, uredis)
    end

    job = @jobs[ident]
    job.analyze

    @jobs.delete(ident) if can_forget?(job)
  end

  private

  def can_forget?(job)
    resps = uredis.pipelined do
      job.completed?
      job.aborted?
    end

    resps.any?
  end
end
