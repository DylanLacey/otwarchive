class CalendarController < ApplicationController

  def index
    @today = Date.today

    # This is listing collections that are accepting signups, and are not yet closed.
    @challenge_collections = (Collection.ge_signups_open.unmoderated.not_closed + Collection.pm_signups_open.unmoderated.not_closed)

    # The following logic checks that today is the day signups opened, or today is between signups_open_at and signups_close_at
    for @challenge_collections.each do |challenge|
      if challenge.signups_open_at.today? || challenge.signups_open_at.past? && !challenge.signups_close_at.past?
        @challenge_to_calendar = challenge
      end
    end

    @challenge_to_calendar
    #@articles = Collections.signups_open_at.past?
    @articles_by_date = @articles.group_by(&:published_on)
    @date = params[:date] ? Date.parse(params[:date]) : Date.today
  end

end