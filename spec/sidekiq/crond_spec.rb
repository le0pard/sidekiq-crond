# frozen_string_literal: true

RSpec.describe Sidekiq::Crond do
  it 'has a version number' do
    expect(Sidekiq::Crond::VERSION).not_to be nil
  end
end
