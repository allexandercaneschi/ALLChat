# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkingHour do
  context 'when on monday 10am' do
    before do
      Time.zone = 'UTC'
      create(:working_hour)
      travel_to '26.10.2020 10:00'.to_datetime
    end

    it 'is considered working hour' do
      expect(described_class.today.open_now?).to be true
    end
  end

  context 'when on sunday 1pm' do
    before do
      Time.zone = 'UTC'
      create(:working_hour, day_of_week: 0, closed_all_day: true)
      travel_to '01.11.2020 13:00'.to_datetime
    end

    it 'is considered out of office' do
      expect(described_class.today.closed_now?).to be true
    end
  end

  context 'when on friday 12:30pm' do
    before do
      Time.zone = 'UTC'
      create(:working_hour)
      travel_to '10.09.2021 12:30'.to_datetime
    end

    it 'is considered to be in business hours' do
      expect(described_class.today.open_now?).to be true
    end
  end

  context 'when on friday 17:30pm' do
    before do
      Time.zone = 'UTC'
      create(:working_hour)
      travel_to '10.09.2021 17:30'.to_datetime
    end

    it 'is considered out of office' do
      expect(described_class.today.closed_now?).to be true
    end
  end

  context 'when open_all_day is true' do
    let(:inbox) { create(:inbox) }

    before do
      Time.zone = 'UTC'
      inbox.working_hours.find_by(day_of_week: 5).update(open_all_day: true)
      travel_to '18.02.2022 11:00'.to_datetime
    end

    it 'updates open hour and close hour' do
      expect(described_class.today.open_all_day?).to be true
      expect(described_class.today.open_hour).to be 0
      expect(described_class.today.open_minutes).to be 0
      expect(described_class.today.close_hour).to be 23
      expect(described_class.today.close_minutes).to be 59
    end

    it 'remains open through the end of the day' do
      travel_to '18.02.2022 23:59:59'.to_datetime do
        expect(described_class.today.open_now?).to be true
      end
    end
  end

  context 'when open_all_day and closed_all_day true at the same time' do
    let(:inbox) { create(:inbox) }

    before do
      Time.zone = 'UTC'
      inbox.working_hours.find_by(day_of_week: 5).update(open_all_day: true)
      travel_to '18.02.2022 11:00'.to_datetime
    end

    it 'throws validation error' do
      working_hour = inbox.working_hours.find_by(day_of_week: 5)
      working_hour.closed_all_day = true
      expect(working_hour.invalid?).to be true
      expect do
        working_hour.save!
      end.to raise_error(ActiveRecord::RecordInvalid,
                         'Validation failed: open_all_day and closed_all_day cannot be true at the same time')
    end
  end

  context 'when on monday 9am in Sydney timezone' do
    let(:inbox) { create(:inbox) }

    before do
      Time.zone = 'Australia/Sydney'
      inbox.update(timezone: 'Australia/Sydney')
      travel_to '10.10.2022 9:00 AEDT'
    end

    it 'is considered working hour' do
      expect(described_class.today.open_now?).to be true
    end
  end

  context 'when there is a lunch break' do
    let(:break_attrs) { { break_start_hour: 12, break_start_minutes: 0, break_end_hour: 13, break_end_minutes: 0 } }

    before do
      Time.zone = 'UTC'
      create(:working_hour, **break_attrs)
    end

    it 'is open before the break' do
      travel_to '26.10.2020 11:59'.to_datetime
      expect(described_class.today.open_now?).to be true
    end

    it 'is closed when the break starts' do
      travel_to '26.10.2020 12:00'.to_datetime
      expect(described_class.today.closed_now?).to be true
    end

    it 'is closed in the middle of the break' do
      travel_to '26.10.2020 12:30'.to_datetime
      expect(described_class.today.closed_now?).to be true
    end

    it 'is open again when the break ends' do
      travel_to '26.10.2020 13:00'.to_datetime
      expect(described_class.today.open_now?).to be true
    end

    it 'is closed after closing time' do
      travel_to '26.10.2020 17:30'.to_datetime
      expect(described_class.today.closed_now?).to be true
    end
  end

  context 'when validating the break' do
    let(:inbox) { create(:inbox) }
    let(:valid_break) { { break_start_hour: 12, break_start_minutes: 0, break_end_hour: 13, break_end_minutes: 30 } }

    def build_hour(**attrs)
      build(:working_hour, inbox: inbox, **attrs)
    end

    it 'accepts working hours without a break' do
      expect(build_hour).to be_valid
    end

    it 'accepts a complete break inside the working hours' do
      expect(build_hour(**valid_break)).to be_valid
    end

    it 'rejects a break with only some of the fields' do
      working_hour = build_hour(break_start_hour: 12, break_start_minutes: 0)

      expect(working_hour).not_to be_valid
      expect(working_hour.errors[:base]).to include('Break needs a start and an end time')
    end

    it 'rejects a break that ends before it starts' do
      working_hour = build_hour(break_start_hour: 13, break_start_minutes: 0, break_end_hour: 12, break_end_minutes: 0)

      expect(working_hour).not_to be_valid
      expect(working_hour.errors[:base]).to include('Break end cannot be before break start')
    end

    it 'rejects a break outside the working hours' do
      working_hour = build_hour(break_start_hour: 16, break_start_minutes: 30, break_end_hour: 18, break_end_minutes: 0)

      expect(working_hour).not_to be_valid
      expect(working_hour.errors[:base]).to include('Break must be inside the working hours')
    end

    it 'rejects out of range break times' do
      working_hour = build_hour(break_start_hour: 25, break_start_minutes: 0, break_end_hour: 26, break_end_minutes: 0)

      expect(working_hour).not_to be_valid
      expect(working_hour.errors[:base]).to include('Break time is out of range')
    end

    it 'clears the break when the day is closed all day' do
      working_hour = build_hour(closed_all_day: true, **valid_break)

      expect(working_hour).to be_valid
      expect(working_hour.break?).to be false
    end
  end
end
