import {
  generateTimeSlots,
  getTime,
  isBreakValid,
  timeSlotParse,
  timeSlotTransform,
  timeZoneOptions,
} from '../businessHour';

describe('#generateTimeSlots', () => {
  it('returns correct number of time slots for 15-minute intervals', () => {
    const slots = generateTimeSlots(15);
    // 24 hours * 4 slots per hour + 1 for 11:59 PM = 97 slots
    expect(slots.length).toStrictEqual(97);
  });

  it('returns correct number of time slots for 30-minute intervals', () => {
    const slots = generateTimeSlots(30);
    // 24 hours * 2 slots per hour + 1 for 11:59 PM = 49 slots
    expect(slots.length).toStrictEqual(49);
  });

  it('returns correct time slots for 4-hour intervals', () => {
    expect(generateTimeSlots(240)).toStrictEqual([
      '12:00 AM',
      '04:00 AM',
      '08:00 AM',
      '12:00 PM',
      '04:00 PM',
      '08:00 PM',
      '11:59 PM',
    ]);
  });

  it('always starts with 12:00 AM', () => {
    expect(generateTimeSlots(15)[0]).toStrictEqual('12:00 AM');
    expect(generateTimeSlots(30)[0]).toStrictEqual('12:00 AM');
    expect(generateTimeSlots(60)[0]).toStrictEqual('12:00 AM');
  });

  it('always ends with 11:59 PM', () => {
    const slots15 = generateTimeSlots(15);
    const slots30 = generateTimeSlots(30);
    const slots60 = generateTimeSlots(60);

    expect(slots15[slots15.length - 1]).toStrictEqual('11:59 PM');
    expect(slots30[slots30.length - 1]).toStrictEqual('11:59 PM');
    expect(slots60[slots60.length - 1]).toStrictEqual('11:59 PM');
  });

  it('includes 11:59 PM even when it would not be in regular intervals', () => {
    const slots = generateTimeSlots(30);
    expect(slots).toContain('11:59 PM');
    expect(slots).toContain('11:30 PM'); // Regular interval
  });

  it('does not duplicate 11:59 PM if it already exists in regular intervals', () => {
    // Test with a step that would naturally include 11:59 PM
    const slots = generateTimeSlots(1); // 1-minute intervals
    const count11_59 = slots.filter(slot => slot === '11:59 PM').length;
    expect(count11_59).toStrictEqual(1);
  });

  it('generates correct time format', () => {
    const slots = generateTimeSlots(60);
    expect(slots).toContain('01:00 AM');
    expect(slots).toContain('12:00 PM');
    expect(slots).toContain('01:00 PM');
    expect(slots).toContain('11:00 PM');
  });

  it('handles edge case with very large step', () => {
    const slots = generateTimeSlots(1440); // 24 hours
    expect(slots).toStrictEqual(['12:00 AM', '11:59 PM']);
  });
});

describe('#getTime', () => {
  it('returns parses 24 hour time correctly', () => {
    expect(getTime(15, 30)).toStrictEqual('03:30 PM');
  });
  it('returns parses 12 hour time correctly', () => {
    expect(getTime(12, 30)).toStrictEqual('12:30 PM');
  });
});

describe('#timeSlotParse', () => {
  it('returns parses correctly', () => {
    const slot = {
      day_of_week: 1,
      open_hour: 1,
      open_minutes: 30,
      close_hour: 4,
      close_minutes: 30,
      closed_all_day: false,
      open_all_day: false,
    };

    expect(timeSlotParse([slot])).toStrictEqual([
      {
        day: 1,
        from: '01:30 AM',
        to: '04:30 AM',
        breakFrom: '',
        breakTo: '',
        valid: true,
        openAllDay: false,
      },
    ]);
  });

  it('parses the break of the day', () => {
    const slot = {
      day_of_week: 1,
      open_hour: 8,
      open_minutes: 0,
      close_hour: 18,
      close_minutes: 0,
      closed_all_day: false,
      open_all_day: false,
      break_start_hour: 12,
      break_start_minutes: 0,
      break_end_hour: 13,
      break_end_minutes: 30,
    };

    expect(timeSlotParse([slot])[0]).toMatchObject({
      breakFrom: '12:00 PM',
      breakTo: '01:30 PM',
    });
  });

  it('keeps a break that starts at midnight hour 0', () => {
    const slot = {
      day_of_week: 1,
      open_hour: 0,
      open_minutes: 0,
      close_hour: 23,
      close_minutes: 59,
      closed_all_day: false,
      open_all_day: true,
      break_start_hour: 0,
      break_start_minutes: 30,
      break_end_hour: 1,
      break_end_minutes: 0,
    };

    expect(timeSlotParse([slot])[0]).toMatchObject({
      breakFrom: '12:30 AM',
      breakTo: '01:00 AM',
    });
  });

  it('ignores the break of a closed day', () => {
    const slot = {
      day_of_week: 0,
      closed_all_day: true,
      break_start_hour: 12,
      break_start_minutes: 0,
      break_end_hour: 13,
      break_end_minutes: 0,
    };

    expect(timeSlotParse([slot])[0]).toMatchObject({
      breakFrom: '',
      breakTo: '',
    });
  });
});

describe('#timeSlotTransform', () => {
  it('returns transforms correctly', () => {
    const slot = {
      day: 1,
      from: '01:30 AM',
      to: '04:30 AM',
      valid: true,
      openAllDay: false,
    };

    expect(timeSlotTransform([slot])).toStrictEqual([
      {
        day_of_week: 1,
        open_hour: 1,
        open_minutes: 30,
        close_hour: 4,
        close_minutes: 30,
        closed_all_day: false,
        open_all_day: false,
        break_start_hour: null,
        break_start_minutes: null,
        break_end_hour: null,
        break_end_minutes: null,
      },
    ]);
  });

  it('transforms the break of the day', () => {
    const slot = {
      day: 1,
      from: '08:00 AM',
      to: '06:00 PM',
      breakFrom: '12:00 PM',
      breakTo: '01:30 PM',
      valid: true,
      openAllDay: false,
    };

    expect(timeSlotTransform([slot])[0]).toMatchObject({
      break_start_hour: 12,
      break_start_minutes: 0,
      break_end_hour: 13,
      break_end_minutes: 30,
    });
  });

  it('sends no break for a closed day', () => {
    const slot = {
      day: 0,
      from: '',
      to: '',
      breakFrom: '12:00 PM',
      breakTo: '01:00 PM',
      valid: false,
      openAllDay: false,
    };

    expect(timeSlotTransform([slot])[0]).toMatchObject({
      closed_all_day: true,
      break_start_hour: null,
      break_end_hour: null,
    });
  });
});

describe('#isBreakValid', () => {
  const day = { from: '08:00 AM', to: '06:00 PM' };

  it('accepts a day without a break', () => {
    expect(isBreakValid({ ...day, breakFrom: '', breakTo: '' })).toBe(true);
  });

  it('accepts a break inside the working hours', () => {
    expect(
      isBreakValid({ ...day, breakFrom: '12:00 PM', breakTo: '01:00 PM' })
    ).toBe(true);
  });

  it('rejects a break with only one time', () => {
    expect(
      isBreakValid({ ...day, breakFrom: '12:00 PM', breakTo: '' })
    ).toBe(false);
  });

  it('rejects a break that ends before it starts', () => {
    expect(
      isBreakValid({ ...day, breakFrom: '01:00 PM', breakTo: '12:00 PM' })
    ).toBe(false);
  });

  it('rejects a break outside the working hours', () => {
    expect(
      isBreakValid({ ...day, breakFrom: '05:30 PM', breakTo: '07:00 PM' })
    ).toBe(false);
  });
});

describe('#timeZoneOptions', () => {
  it('returns transforms correctly', () => {
    expect(timeZoneOptions()[0]).toStrictEqual({
      value: 'Etc/GMT+12',
      label: 'International Date Line West (GMT−12:00)',
    });
  });
});
