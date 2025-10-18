# frozen_string_literal: true

class User < ApplicationRecord
  # Includes
  include Rodauth::Rails.model
  include Verifiable
  include Tokenable

  # Associations are in Tokenable concern:
  # has_many :jwt_denylists, dependent: :destroy
  # has_many :refresh_tokens, dependent: :destroy

  # Browsing data associations
  has_many :page_visits, dependent: :destroy
  has_many :tab_aggregates, through: :page_visits

  # Validations
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :first_name, presence: true, allow_blank: false
  validates :last_name, presence: true, allow_blank: false

  # Callbacks are in Verifiable concern:
  # before_save :sync_status_with_is_verified

  # Instance methods
  def valid_password?(password)
    return false if password_hash.blank?

    BCrypt::Password.new(password_hash) == password
  rescue BCrypt::Errors::InvalidHash
    false
  end

  # Override isVerified= to sync with status
  # TODO: Refactor to use snake_case (is_verified) with migration
  def isVerified=(value)
    super(value)
    self.status = value ? :verified : :unverified
  end
end
