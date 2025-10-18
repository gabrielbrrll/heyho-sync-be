# frozen_string_literal: true

module Api
  module V1
    class InsightsController < BaseController
      before_action :authenticate_request
      before_action :set_target_user

      # GET /api/v1/insights/daily_summary
      def daily_summary
        date = parse_date(params[:date]) || Time.current.beginning_of_day
        yesterday = date - 1.day

        today_visits = @target_user.page_visits.where('visited_at >= ? AND visited_at < ?', date, date + 1.day)
        yesterday_visits = @target_user.page_visits.where('visited_at >= ? AND visited_at < ?', yesterday, date)

        # Calculate totals
        total_time = today_visits.sum(:duration_seconds) || 0
        total_sessions = today_visits.count
        unique_sites = today_visits.distinct.count(:domain)
        unique_domains = today_visits.where.not(domain: nil).distinct.pluck(:domain).count

        # Find most visited site
        most_visited = today_visits.group(:domain)
                                   .count
                                   .max_by { |_domain, count| count }
        most_visited_site = most_visited ? most_visited[0] : nil

        # Find longest session
        longest = today_visits.order(duration_seconds: :desc).first
        longest_session = if longest && longest.duration_seconds
                            {
                              url: longest.url,
                              duration: longest.duration_seconds
                            }
                          end

        # Compare with yesterday
        yesterday_time = yesterday_visits.sum(:duration_seconds) || 0
        yesterday_sessions = yesterday_visits.count
        time_diff = total_time - yesterday_time
        sessions_diff = total_sessions - yesterday_sessions

        render_json_response(
          success: true,
          data: {
            date: date.to_date.to_s,
            total_time_seconds: total_time,
            total_sessions: total_sessions,
            unique_sites: unique_sites,
            unique_domains: unique_domains,
            most_visited_site: most_visited_site,
            longest_session: longest_session,
            comparison: {
              vs_yesterday: {
                time_diff: format_diff(time_diff),
                sessions_diff: format_diff(sessions_diff)
              }
            }
          }
        )
      end

      # GET /api/v1/insights/top_sites
      def top_sites
        period = params[:period] || 'today'
        limit = [params[:limit]&.to_i || 10, 50].min

        date_range = case period
                     when 'today'
                       Time.current.beginning_of_day..Time.current.end_of_day
                     when 'week'
                       7.days.ago.beginning_of_day..Time.current.end_of_day
                     when 'month'
                       30.days.ago.beginning_of_day..Time.current.end_of_day
                     else
                       Time.current.beginning_of_day..Time.current.end_of_day
                     end

        visits = @target_user.page_visits.where(visited_at: date_range).where.not(domain: nil)

        # Group by domain and calculate stats
        total_time = visits.sum(:duration_seconds) || 1 # Avoid division by zero

        sites = visits.group(:domain)
                      .select('domain,
                               SUM(duration_seconds) as total_time,
                               COUNT(*) as visit_count,
                               AVG(duration_seconds) as avg_duration,
                               MAX(visited_at) as last_visit')
                      .order('total_time DESC')
                      .limit(limit)
                      .map do |site|
          {
            domain: site.domain,
            total_time_seconds: site.total_time.to_i,
            visit_count: site.visit_count,
            percentage_of_total: total_time.positive? ? ((site.total_time.to_f / total_time) * 100).round(1) : 0,
            avg_session_duration: site.avg_duration.to_i,
            last_visited_at: site.last_visit
          }
        end

        render_json_response(
          success: true,
          data: {
            period: period,
            sites: sites
          }
        )
      end

      # GET /api/v1/insights/recent_activity
      def recent_activity
        limit = [params[:limit]&.to_i || 20, 100].min

        sessions = @target_user.page_visits
                               .order(visited_at: :desc)
                               .limit(limit)
                               .map do |visit|
          duration = visit.duration_seconds || 0
          is_long_session = duration > 1800 # 30 minutes

          {
            id: visit.id,
            url: visit.url,
            title: visit.title,
            domain: visit.domain,
            visited_at: visit.visited_at,
            duration: duration,
            is_long_session: is_long_session
          }
        end

        render_json_response(
          success: true,
          data: {
            sessions: sessions
          }
        )
      end

      private

      # Authenticate using JWT token or service secret
      def authenticate_request
        service_token = request.headers['X-Service-Token']
        auth_header = request.headers['Authorization']

        Rails.logger.info "DEBUG AUTH: service_token=#{service_token.present?}, auth_header=#{auth_header.inspect}"

        # Check for service token first (simple service-to-service auth)
        if service_token.present? && service_token == ENV['SERVICE_SECRET']
          Rails.logger.info "DEBUG AUTH: Using service token"
          return true
        end

        # Otherwise, require JWT authentication
        unless auth_header&.start_with?('Bearer ')
          Rails.logger.info "DEBUG AUTH: No valid auth header"
          render_error_response(message: 'Authentication required', status: :unauthorized)
          return false
        end

        token = auth_header.sub('Bearer ', '')
        Rails.logger.info "DEBUG AUTH: Token=#{token[0..20]}..."
        @decoded_token = ::Authentication::TokenService.decode_jwt_token(token)

        Rails.logger.info "DEBUG AUTH: decoded_token=#{@decoded_token.inspect}"

        unless @decoded_token
          render_error_response(message: 'Invalid or expired token', status: :unauthorized)
          return false
        end

        true
      end

      # Find the target user based on email parameter or JWT token
      def set_target_user
        email = params[:email].presence || params[:user_email].presence

        Rails.logger.info "DEBUG: email=#{email.inspect}, decoded_token=#{@decoded_token.inspect}"

        @target_user = if email.present?
                         # Service-to-service call with email parameter
                         User.find_by(email: email)
                       elsif @decoded_token
                         # Direct user call with JWT
                         Rails.logger.info "DEBUG: Looking for user with id=#{@decoded_token['sub']}"
                         User.find_by(id: @decoded_token['sub'])
                       end

        Rails.logger.info "DEBUG: target_user=#{@target_user.inspect}"

        unless @target_user
          render_error_response(message: 'User not found', status: :not_found)
          return false
        end

        true
      end

      def parse_date(date_string)
        return nil unless date_string

        Date.parse(date_string).beginning_of_day
      rescue ArgumentError
        nil
      end

      def format_diff(value)
        return value.to_s if value.zero?

        value.positive? ? "+#{value}" : value.to_s
      end
    end
  end
end
