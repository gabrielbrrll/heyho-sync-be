# frozen_string_literal: true

module Api
  module V1
    class BrowsingDataController < BaseController
      before_action :authenticate_request

      # GET /api/v1/browsing_data
      # Accepts optional email parameter for service-to-service calls
      def index
        target_user = find_target_user
        return unless target_user

        @page_visits = target_user.page_visits
                                   .order(visited_at: :desc)
                                   .limit(page_limit)
                                   .offset(page_offset)

        @tab_aggregates = target_user.tab_aggregates
                                      .order(closed_at: :desc)
                                      .limit(page_limit)
                                      .offset(page_offset)

        render_json_response(
          success: true,
          data: {
            page_visits: @page_visits.as_json(
              only: [:id, :url, :title, :visited_at, :tab_id, :domain, :duration_seconds,
                     :active_duration_seconds, :engagement_rate, :idle_periods, :last_heartbeat,
                     :anonymous_client_id, :created_at, :updated_at]
            ),
            tab_aggregates: @tab_aggregates.as_json(
              only: [:id, :page_visit_id, :total_time_seconds, :active_time_seconds,
                     :scroll_depth_percent, :closed_at, :domain_durations, :page_count,
                     :current_url, :current_domain, :statistics, :created_at, :updated_at]
            ),
            pagination: {
              page: current_page,
              per_page: page_limit,
              total_page_visits: target_user.page_visits.count,
              total_tab_aggregates: target_user.tab_aggregates.count
            }
          }
        )
      end

      # GET /api/v1/browsing_data/summary
      # Accepts optional email parameter for service-to-service calls
      def summary
        target_user = find_target_user
        return unless target_user

        today = Time.current.beginning_of_day
        week_ago = 7.days.ago

        page_visits_today = target_user.page_visits.where('visited_at >= ?', today)
        page_visits_week = target_user.page_visits.where('visited_at >= ?', week_ago)

        # Count visits (we don't have duration/engagement data in this schema)
        # Top domains would require domain column which we also don't have
        # For now, return basic counts

        render_json_response(
          success: true,
          data: {
            today: {
              page_visits_count: page_visits_today.count
            },
            week: {
              page_visits_count: page_visits_week.count
            },
            message: "Summary with basic counts (schema doesn't include duration/engagement)"
          }
        )
      end

      private

      # Authenticate using JWT token (for service-to-service calls)
      # OR using service secret (for internal services like Syrupy)
      def authenticate_request
        service_token = request.headers['X-Service-Token']

        # Check for service token first (simple service-to-service auth)
        if service_token.present? && service_token == ENV['SERVICE_SECRET']
          return true
        end

        # Otherwise, require JWT authentication
        auth_header = request.headers['Authorization']
        unless auth_header&.start_with?('Bearer ')
          render_error_response(message: 'Authentication required', status: :unauthorized)
          return false
        end

        token = auth_header.sub('Bearer ', '')
        @decoded_token = ::Authentication::TokenService.decode_jwt_token(token)

        unless @decoded_token
          render_error_response(message: 'Invalid or expired token', status: :unauthorized)
          return false
        end

        true
      end

      # Find the target user based on email parameter or JWT token
      def find_target_user
        email = params[:email].presence || params[:user_email].presence

        if email.present?
          # Service-to-service call with email parameter
          user = User.find_by(email: email)
          unless user
            render_error_response(message: 'User not found', status: :not_found)
            return nil
          end
          user
        elsif @decoded_token
          # Direct user call with JWT
          user = User.find_by(id: @decoded_token['sub'])
          unless user
            render_error_response(message: 'User not found', status: :not_found)
            return nil
          end
          user
        else
          render_error_response(message: 'Email or user identification required', status: :bad_request)
          nil
        end
      end

      def current_page
        params[:page]&.to_i || 1
      end

      def page_limit
        limit = params[:per_page]&.to_i || 50
        [limit, 100].min # Max 100 items per page
      end

      def page_offset
        (current_page - 1) * page_limit
      end
    end
  end
end
