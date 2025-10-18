# Phase 3: Testing Strategy

## Overview

Comprehensive testing approach for pattern detection, reading list, and research sessions features.

---

## Test Coverage Goals

- **Models:** 95%+ coverage
- **Controllers:** 90%+ coverage
- **Services:** 95%+ coverage
- **Integration:** All API endpoints tested

---

## 1. Model Specs

### ReadingListItem Spec

**File:** `spec/models/reading_list_item_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe ReadingListItem do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:page_visit).optional }
  end

  describe 'validations' do
    subject { build(:reading_list_item) }

    it { should validate_presence_of(:url) }
    it { should validate_uniqueness_of(:url).scoped_to(:user_id) }
    it { should validate_inclusion_of(:status).in_array(%w[unread reading completed dismissed]) }
  end

  describe 'scopes' do
    let(:user) { create(:user) }
    let!(:unread_item) { create(:reading_list_item, user:, status: 'unread') }
    let!(:completed_item) { create(:reading_list_item, user:, status: 'completed') }

    it 'filters by unread status' do
      expect(described_class.unread).to contain_exactly(unread_item)
    end

    it 'filters by completed status' do
      expect(described_class.completed).to contain_exactly(completed_item)
    end
  end

  describe 'callbacks' do
    context 'before_validation' do
      it 'extracts domain from URL' do
        item = build(:reading_list_item, url: 'https://www.example.com/article', domain: nil)
        item.valid?
        expect(item.domain).to eq('example.com')
      end

      it 'sets added_at on create' do
        item = create(:reading_list_item, added_at: nil)
        expect(item.added_at).to be_present
      end
    end

    context 'after_update' do
      let(:item) { create(:reading_list_item, status: 'unread') }

      it 'sets completed_at when marked as completed' do
        expect {
          item.update!(status: 'completed')
        }.to change { item.reload.completed_at }.from(nil).to(be_present)
      end

      it 'sets dismissed_at when marked as dismissed' do
        expect {
          item.update!(status: 'dismissed')
        }.to change { item.reload.dismissed_at }.from(nil).to(be_present)
      end
    end
  end

  describe '.completion_rate' do
    let(:user) { create(:user) }

    before do
      create_list(:reading_list_item, 3, user:, status: 'completed')
      create_list(:reading_list_item, 2, user:, status: 'unread')
      create(:reading_list_item, user:, status: 'dismissed')
    end

    it 'calculates completion rate excluding dismissed' do
      expect(described_class.completion_rate(user)).to eq(60.0)
    end
  end

  describe '#mark_completed!' do
    let(:item) { create(:reading_list_item, status: 'unread') }

    it 'marks item as completed' do
      item.mark_completed!
      expect(item.reload.status).to eq('completed')
      expect(item.completed_at).to be_present
    end
  end
end
```

---

### ResearchSession Spec

**File:** `spec/models/research_session_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe ResearchSession do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should have_many(:research_session_tabs).dependent(:destroy) }
    it { should have_many(:page_visits).through(:research_session_tabs) }
  end

  describe 'validations' do
    it { should validate_presence_of(:session_name) }
    it { should validate_presence_of(:session_start) }
    it { should validate_presence_of(:session_end) }
    it { should validate_numericality_of(:tab_count).is_greater_than(0) }

    it 'validates session_end is after session_start' do
      session = build(:research_session, session_start: 2.hours.ago, session_end: 3.hours.ago)
      expect(session).not_to be_valid
      expect(session.errors[:session_end]).to include('must be after session start')
    end
  end

  describe 'scopes' do
    let(:user) { create(:user) }
    let!(:detected_session) { create(:research_session, user:, status: 'detected') }
    let!(:saved_session) { create(:research_session, user:, status: 'saved') }

    it 'filters by detected status' do
      expect(described_class.detected).to contain_exactly(detected_session)
    end

    it 'filters by saved status' do
      expect(described_class.saved).to contain_exactly(saved_session)
    end
  end

  describe '#add_tabs!' do
    let(:session) { create(:research_session) }
    let(:page_visits) { create_list(:page_visit, 3, user: session.user) }

    it 'creates session tabs from page visit IDs' do
      expect {
        session.add_tabs!(page_visits.map(&:id))
      }.to change(session.research_session_tabs, :count).by(3)
    end

    it 'updates tab_count' do
      expect {
        session.add_tabs!(page_visits.map(&:id))
      }.to change { session.reload.tab_count }.from(0).to(3)
    end

    it 'sets tab order' do
      session.add_tabs!(page_visits.map(&:id))
      tabs = session.research_session_tabs.order(:tab_order)
      expect(tabs.map(&:tab_order)).to eq([1, 2, 3])
    end
  end

  describe '#tabs_for_restoration' do
    let(:session) { create(:research_session) }

    before do
      create(:research_session_tab, research_session: session, url: 'https://example.com/1', tab_order: 1)
      create(:research_session_tab, research_session: session, url: 'https://example.com/2', tab_order: 2)
    end

    it 'returns tabs in correct order' do
      tabs = session.tabs_for_restoration
      expect(tabs.map { |t| t[:url] }).to eq(['https://example.com/1', 'https://example.com/2'])
    end
  end

  describe '#mark_restored!' do
    let(:session) { create(:research_session, status: 'saved', restore_count: 0) }

    it 'increments restore_count' do
      expect {
        session.mark_restored!
      }.to change { session.reload.restore_count }.by(1)
    end

    it 'updates last_restored_at' do
      expect {
        session.mark_restored!
      }.to change { session.reload.last_restored_at }.from(nil).to(be_present)
    end
  end
end
```

---

## 2. Request Specs

### Patterns API Spec

**File:** `spec/requests/api/v1/patterns_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe 'Patterns API' do
  let(:user) { create(:user) }
  let(:token) { generate_jwt_token(user) }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }

  describe 'GET /api/v1/patterns/hoarder-tabs' do
    before do
      # Create hoarder tabs (high duration, low engagement)
      create(:page_visit, user:, duration_seconds: 1000, engagement_rate: 0.01)
      create(:page_visit, user:, duration_seconds: 2000, engagement_rate: 0.02)
      # Create normal tabs (not hoarders)
      create(:page_visit, user:, duration_seconds: 100, engagement_rate: 0.8)
    end

    it 'returns hoarder tabs' do
      get '/api/v1/patterns/hoarder-tabs', headers:

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json['success']).to be true
      expect(json['data']['hoarder_tabs'].size).to eq(2)
      expect(json['data']['total_count']).to eq(2)
    end

    it 'respects min_duration parameter' do
      get '/api/v1/patterns/hoarder-tabs?min_duration=1500', headers:

      json = response.parsed_body
      expect(json['data']['hoarder_tabs'].size).to eq(1)
    end

    it 'respects max_engagement parameter' do
      get '/api/v1/patterns/hoarder-tabs?max_engagement=0.015', headers:

      json = response.parsed_body
      expect(json['data']['hoarder_tabs'].size).to eq(1)
    end
  end

  describe 'GET /api/v1/patterns/serial-openers' do
    before do
      # Create serial opens for medium.com (4 times)
      4.times { create(:page_visit, user:, domain: 'medium.com', duration_seconds: 60) }
      # Create single visit for other domain
      create(:page_visit, user:, domain: 'example.com', duration_seconds: 60)
    end

    it 'returns serial opener domains' do
      get '/api/v1/patterns/serial-openers', headers:

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json['success']).to be true
      expect(json['data']['serial_openers'].size).to eq(1)
      expect(json['data']['serial_openers'].first['domain']).to eq('medium.com')
      expect(json['data']['serial_openers'].first['open_count']).to eq(4)
    end
  end

  describe 'GET /api/v1/patterns/research-sessions' do
    before do
      # Create research session (6 tabs from stackoverflow in 1 hour)
      base_time = 2.hours.ago
      6.times do |i|
        create(:page_visit, user:, domain: 'stackoverflow.com', visited_at: base_time + i.minutes)
      end
      # Single tab from other domain (not a session)
      create(:page_visit, user:, domain: 'github.com', visited_at: 1.hour.ago)
    end

    it 'returns research sessions' do
      get '/api/v1/patterns/research-sessions', headers:

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json['success']).to be true
      expect(json['data']['research_sessions'].size).to be >= 1
    end
  end
end
```

---

### Reading List API Spec

**File:** `spec/requests/api/v1/reading_list_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe 'Reading List API' do
  let(:user) { create(:user) }
  let(:token) { generate_jwt_token(user) }
  let(:headers) { { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' } }

  describe 'GET /api/v1/reading-list' do
    before do
      create_list(:reading_list_item, 3, user:, status: 'unread')
      create(:reading_list_item, user:, status: 'completed')
    end

    it 'returns reading list items' do
      get '/api/v1/reading-list', headers:

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json['success']).to be true
      expect(json['data']['items'].size).to eq(4)
      expect(json['data']['stats']['total_unread']).to eq(3)
      expect(json['data']['stats']['total_completed']).to eq(1)
    end

    it 'filters by status' do
      get '/api/v1/reading-list?status=unread', headers:

      json = response.parsed_body
      expect(json['data']['items'].size).to eq(3)
    end
  end

  describe 'POST /api/v1/reading-list' do
    let(:valid_params) do
      {
        reading_list_item: {
          url: 'https://example.com/article',
          title: 'Test Article',
          added_from: 'manual_save'
        }
      }
    end

    it 'creates a new reading list item' do
      expect {
        post '/api/v1/reading-list', headers:, params: valid_params.to_json
      }.to change(ReadingListItem, :count).by(1)

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json['success']).to be true
      expect(json['data']['url']).to eq('https://example.com/article')
    end

    it 'rejects duplicate URLs' do
      create(:reading_list_item, user:, url: 'https://example.com/article')

      post '/api/v1/reading-list', headers:, params: valid_params.to_json

      expect(response).to have_http_status(:unprocessable_entity)
      json = response.parsed_body
      expect(json['success']).to be false
    end
  end

  describe 'POST /api/v1/reading-list/bulk' do
    let(:bulk_params) do
      {
        items: [
          { url: 'https://example.com/1', title: 'Article 1' },
          { url: 'https://example.com/2', title: 'Article 2' }
        ],
        skip_duplicates: true
      }
    end

    it 'creates multiple items' do
      expect {
        post '/api/v1/reading-list/bulk', headers:, params: bulk_params.to_json
      }.to change(ReadingListItem, :count).by(2)

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json['data']['created']).to eq(2)
    end
  end

  describe 'PATCH /api/v1/reading-list/:id' do
    let(:item) { create(:reading_list_item, user:, status: 'unread') }

    it 'updates item status' do
      patch "/api/v1/reading-list/#{item.id}", headers:, params: { status: 'completed' }.to_json

      expect(response).to have_http_status(:ok)
      expect(item.reload.status).to eq('completed')
    end
  end

  describe 'DELETE /api/v1/reading-list/:id' do
    let!(:item) { create(:reading_list_item, user:) }

    it 'deletes the item' do
      expect {
        delete "/api/v1/reading-list/#{item.id}", headers:
      }.to change(ReadingListItem, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end
end
```

---

## 3. Service Specs

### Pattern Detection Service Spec

**File:** `spec/services/patterns/detection_service_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe Patterns::DetectionService do
  let(:user) { create(:user) }

  describe '.call' do
    before do
      # Create test data
      create(:page_visit, user:, duration_seconds: 1000, engagement_rate: 0.01)
      3.times { create(:page_visit, user:, domain: 'medium.com', duration_seconds: 60) }
    end

    it 'detects all pattern types' do
      results = described_class.call(user)

      expect(results).to have_key(:hoarder_tabs)
      expect(results).to have_key(:serial_openers)
      expect(results).to have_key(:research_sessions)
    end

    it 'detects only specified pattern types' do
      results = described_class.call(user, pattern_types: [:hoarder])

      expect(results).to have_key(:hoarder_tabs)
      expect(results).not_to have_key(:serial_openers)
    end
  end
end
```

---

## 4. Factory Definitions

**File:** `spec/factories/reading_list_items.rb`

```ruby
FactoryBot.define do
  factory :reading_list_item do
    association :user
    sequence(:url) { |n| "https://example.com/article-#{n}" }
    title { Faker::Lorem.sentence }
    domain { 'example.com' }
    status { 'unread' }
    added_from { 'manual_save' }
    added_at { Time.current }

    trait :completed do
      status { 'completed' }
      completed_at { Time.current }
    end

    trait :scheduled do
      scheduled_for { 1.day.from_now }
    end
  end
end
```

**File:** `spec/factories/research_sessions.rb`

```ruby
FactoryBot.define do
  factory :research_session do
    association :user
    session_name { "#{Faker::Internet.domain_name} Research - #{Time.current.strftime('%b %d, %l:%M %p')}" }
    session_start { 2.hours.ago }
    session_end { 1.hour.ago }
    tab_count { 5 }
    primary_domain { 'stackoverflow.com' }
    domains { ['stackoverflow.com', 'github.com'] }
    topics { ['react', 'testing'] }
    status { 'detected' }

    trait :saved do
      status { 'saved' }
      saved_at { Time.current }
    end

    trait :with_tabs do
      after(:create) do |session|
        create_list(:research_session_tab, 3, research_session: session)
      end
    end
  end
end
```

---

## 5. Integration Tests

### End-to-End Flow Test

**File:** `spec/integration/pattern_workflow_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe 'Pattern Detection Workflow' do
  let(:user) { create(:user) }

  it 'completes full workflow from detection to reading list' do
    # Step 1: Create browsing data
    create(:page_visit, user:, duration_seconds: 1000, engagement_rate: 0.01, url: 'https://example.com/article')

    # Step 2: Detect patterns
    results = Patterns::DetectionService.call(user)
    expect(results[:hoarder_tabs].size).to eq(1)

    hoarder_tab = results[:hoarder_tabs].first

    # Step 3: Add to reading list
    item = user.reading_list_items.create!(
      url: hoarder_tab[:url],
      title: hoarder_tab[:title],
      domain: hoarder_tab[:domain],
      added_from: 'hoarder_detection'
    )

    expect(item).to be_persisted
    expect(item.status).to eq('unread')

    # Step 4: Mark as completed
    item.mark_completed!
    expect(item.status).to eq('completed')
    expect(item.completed_at).to be_present
  end
end
```

---

## 6. Performance Tests

**File:** `spec/performance/pattern_detection_performance_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe 'Pattern Detection Performance' do
  let(:user) { create(:user) }

  before do
    # Create realistic dataset
    create_list(:page_visit, 1000, user:)
  end

  it 'detects hoarder tabs in under 100ms', :performance do
    duration = Benchmark.realtime do
      Patterns::HoarderDetector.new(user, {}).call
    end

    expect(duration).to be < 0.1
  end

  it 'detects serial openers in under 100ms', :performance do
    duration = Benchmark.realtime do
      Patterns::SerialOpenerDetector.new(user, {}).call
    end

    expect(duration).to be < 0.1
  end
end
```

---

## Running Tests

### Full Test Suite
```bash
bundle exec rspec
```

### Specific Files
```bash
bundle exec rspec spec/models/reading_list_item_spec.rb
bundle exec rspec spec/requests/api/v1/patterns_spec.rb
```

### With Coverage
```bash
COVERAGE=true bundle exec rspec
open coverage/index.html
```

### Performance Tests
```bash
bundle exec rspec --tag performance
```

---

## CI/CD Integration

**File:** `.github/workflows/phase3-tests.yml`

```yaml
name: Phase 3 Tests

on:
  pull_request:
    paths:
      - 'app/models/reading_list_item.rb'
      - 'app/models/research_session*.rb'
      - 'app/controllers/api/v1/patterns_controller.rb'
      - 'app/services/patterns/**'
      - 'spec/**/*_spec.rb'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2
          bundler-cache: true
      - name: Setup Database
        run: |
          bundle exec rails db:create
          bundle exec rails db:migrate
      - name: Run Tests
        run: bundle exec rspec --format documentation
      - name: Upload Coverage
        uses: codecov/codecov-action@v3
```

---

**Status:** Ready for Implementation
**Last Updated:** 2025-10-16
