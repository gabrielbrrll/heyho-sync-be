# frozen_string_literal: true

Rails.application.routes.draw do
  # Mount letter_opener web interface in development
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Email verification endpoints (outside Rodauth mount to avoid conflicts)
  namespace :api do
    namespace :v1 do
      post 'verify-email', to: 'verification#verify_email'
      post 'resend-verification', to: 'verification#resend_verification'

      # Password reset endpoints
      post 'reset-password-request', to: 'password_reset#request_reset'
      post 'reset-password', to: 'password_reset#reset_password'

      # Data sync endpoints
      post 'data/sync', to: 'data_sync#create'

      # Browsing data endpoints (for fetching synced data)
      get 'browsing_data', to: 'browsing_data#index'
      get 'browsing_data/summary', to: 'browsing_data#summary'

      # Insights endpoints
      get 'insights/daily_summary', to: 'insights#daily_summary'
      get 'insights/top_sites', to: 'insights#top_sites'
      get 'insights/recent_activity', to: 'insights#recent_activity'
    end
  end

  # Mount Rodauth routes under /auth prefix to avoid conflicts
  mount RodauthApp.app => "/api/v1/auth"

  # API routes
  namespace :api do
    namespace :v1 do
      # Rodauth authentication routes are now available

        # User management routes - for additional user profile operations
        resource :users, only: [] do
          collection do
            get 'me'
            patch 'me', action: :update
            patch 'me/password', action: :update_password
          end
        end

        # Health check
        get 'health', to: proc { [200, {}, ['OK']] }
    end
  end

  # Root route for API
  root to: proc { [200, { 'Content-Type' => 'application/json' }, [{ message: 'HeyHo Sync API' }.to_json]] }
end