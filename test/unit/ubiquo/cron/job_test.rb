require File.dirname(__FILE__) + "/../../../test_helper.rb"
require 'tempfile'
require 'socket'
require 'etc'

class Ubiquo::Cron::JobTest < ActiveSupport::TestCase

  def setup
    @job = Ubiquo::Cron::Job.new
    Rake::Task.define_task :ubiquo_cron_test do; end
    Rake::Task.define_task :ubiquo_cron_stds_test do
      $stdout.puts "out"
      $stderr.puts "err"
    end
  end

  def teardown
    Rake.application.instance_variable_get('@tasks').delete('ubiquo_cron_test')
    Rake.application.instance_variable_get('@tasks').delete('ubiquo_cron_stds_test')
  end

  test "Should be able to run a job" do
    assert_respond_to @job, :run
    Rake::Task['ubiquo_cron_test'].expects(:invoke).returns(true)
    assert @job.run('ubiquo_cron_test')
  end

  test "Should be able to determine if a job has been executed" do
    assert_respond_to @job, :invoked?
    assert !@job.invoked?
    assert @job.run('ubiquo_cron_test')
    assert @job.invoked?
  end

  test "Should be able to get stdout, stderr of a job" do
    assert_respond_to @job, :stdout
    assert @job.run('ubiquo_cron_stds_test')
    assert_equal "out\n", @job.stdout
    assert_equal "err\n", @job.stderr
  end

  test "Should be able to log results to a specified log file" do
    logfile = Tempfile.new('ubiquo_cron_stds_test')
    logger = Logger.new(logfile.path, Logger::DEBUG)
    job = Ubiquo::Cron::Job.new(logger)
    job.run('ubiquo_cron_stds_test')
    contents = File.read(logfile.path)
    hostname = Socket.gethostname
    username = Etc.getpwuid(Process.uid).name
    date     = Time.now.strftime("%b %d")
    assert_match(/^#{date}/, contents)
    assert_match(/#{hostname}/, contents)
    assert_match(/#{username}/, contents)
    assert_match(/#{$$}/, contents)
    assert_match(/seconds elapsed/, contents)
    assert_match(/ubiquo_cron_stds_test/, contents)
  end

  test "Should be able to log debug messages when debug is active" do
    logfile = Tempfile.new('ubiquo_cron_test')
    logger = Logger.new(logfile.path, Logger::DEBUG)
    job = Ubiquo::Cron::Job.new(logger, true) # Debug activated
    job.run('ubiquo_cron_stds_test')
    contents = File.read(logfile.path)
    assert_match(/DEBUG Standard output/, contents)
    assert_match(/DEBUG Standard error/, contents)
  end

  test "Lockfile shouldn't fail when task has special characters" do
    assert !@job.run('/dsada/ $$$$$ \\\\\\')
    assert_respond_to @job, :stdout
    assert @job.backtrace
  end

  test "Should catch and log exceptions" do
    logfile = Tempfile.new('ubiquo_cron_test')
    logger = Logger.new(logfile.path, Logger::DEBUG)
    job = Ubiquo::Cron::Job.new(logger)
    assert_nothing_raised do
      job.run('krash')
    end
    contents = File.read(logfile.path)
    assert_match(/Don't know how to build task 'krash'/, contents)
  end

  test "Same task execution shouldn't pile up" do
    Rake::Task.define_task :ubiquo_cron_sleep_test do; sleep 2; end
    threads    = []
    task       = 'ubiquo_cron_sleep_test'
    logfile    = Tempfile.new task
    logger     = Logger.new(logfile.path, Logger::DEBUG)

    Thread.abort_on_exception = true

    2.times do
      threads << Thread.new(logger,task) { |logger,task| Ubiquo::Cron::Job.new(logger).run(task) }
    end

    threads.each { |t| t.join }

    contents = File.read(logfile.path)
    assert_match(/Exception message: surpased retries/, contents)
    assert_match(/lockfile.rb/, contents)
  end

  test "Should send email when a task error occurs" do
    Ubiquo::Cron::Crontab.configure do |config|
      config.mailto = 'test@test.com'
    end
    task = 'ubiquo_cron_mail_test'
    Rake::Task.define_task task.to_sym do; krash; end
    logfile = Tempfile.new task
    logger  = Logger.new(logfile.path, Logger::DEBUG)
    job     = Ubiquo::Cron::Job.new(logger)
    assert_difference 'ActionMailer::Base.deliveries.size', +1 do
      job.run task
    end
    error_mail = ActionMailer::Base.deliveries.first

    assert_match /CRON JOB ERROR/, error_mail.subject
    assert_equal error_mail.to[0], 'test@test.com'
    assert_match /krash/, error_mail.body
  end

  test "Should not send emails when no recipients are set" do
    task       = '3+3'
    recipients = nil
    logfile    = Tempfile.new task
    logger     = Logger.new(logfile.path, Logger::DEBUG)
    job        = Ubiquo::Cron::Job.new(logger,recipients)
    assert_no_difference 'ActionMailer::Base.deliveries.size' do
      job.run(task,:script)
    end
  end

  test "Should be able to run script/runner like commands" do
    task = 'a = 3 * 2; puts a'
    logfile = Tempfile.new task
    logger  = Logger.new(logfile.path, Logger::DEBUG)
    job = Ubiquo::Cron::Job.new(logger)
    assert job.run(task, :script)
    assert_equal '6', job.stdout.strip
  end

  # TODO: Let the directory for locks to be configurable
  # TODO: Refactor crontab.instance and job interface
  # TODO: Comment public methods
  # TODO: Refactor tests
  # TODO: Deal with multiple environments
  # TODO: Install with capistrano

end
