<script>
import parse from 'date-fns/parse';
import differenceInMinutes from 'date-fns/differenceInMinutes';
import { generateTimeSlots, isBreakValid } from '../helpers/businessHour';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextSelect from 'dashboard/components-next/select/Select.vue';

const timeSlots = generateTimeSlots(30);

const groupByPeriod = slots =>
  ['AM', 'PM']
    .map(period => ({
      label: period,
      options: slots
        .filter(s => s.endsWith(period))
        .map(s => ({ value: s, label: s })),
    }))
    .filter(g => g.options.length);

export default {
  components: {
    Icon,
    NextSelect,
  },
  props: {
    dayName: {
      type: String,
      required: true,
    },
    timeSlot: {
      type: Object,
      default: () => ({
        from: '',
        to: '',
      }),
    },
  },
  emits: ['update'],
  computed: {
    fromTimeSlots() {
      return groupByPeriod(timeSlots);
    },
    toTimeSlots() {
      return groupByPeriod(timeSlots.filter(slot => slot !== '12:00 AM'));
    },
    breakTimeSlots() {
      return groupByPeriod(timeSlots.filter(slot => slot !== '12:00 AM'));
    },
    isDayEnabled: {
      get() {
        return Boolean(this.timeSlot.from && this.timeSlot.to);
      },
      set(value) {
        const newSlot = value
          ? {
              ...this.timeSlot,
              from: timeSlots[0],
              to: timeSlots[16],
              breakFrom: '',
              breakTo: '',
              valid: true,
              openAllDay: false,
            }
          : {
              ...this.timeSlot,
              from: '',
              to: '',
              breakFrom: '',
              breakTo: '',
              valid: false,
              openAllDay: false,
            };
        this.$emit('update', newSlot);
      },
    },
    fromTime: {
      get() {
        return this.timeSlot.from;
      },
      set(value) {
        const fromDate = parse(value, 'hh:mm a', new Date());
        const slot = { ...this.timeSlot, from: value };
        const valid =
          differenceInMinutes(this.toDate, fromDate) / 60 > 0 &&
          isBreakValid(slot);
        this.$emit('update', { ...slot, valid });
      },
    },
    toTime: {
      get() {
        return this.timeSlot.to;
      },
      set(value) {
        const toDate = parse(value, 'hh:mm a', new Date());
        const slot = { ...this.timeSlot, to: value };
        if (value === '12:00 AM') {
          this.$emit('update', { ...slot, valid: isBreakValid(slot) });
        } else {
          const valid =
            differenceInMinutes(toDate, this.fromDate) / 60 > 0 &&
            isBreakValid(slot);
          this.$emit('update', { ...slot, valid });
        }
      },
    },
    fromDate() {
      return parse(this.fromTime, 'hh:mm a', new Date());
    },
    toDate() {
      return parse(this.toTime, 'hh:mm a', new Date());
    },
    breakMinutes() {
      if (!this.hasBreak || this.hasBreakError) return 0;

      return differenceInMinutes(
        parse(this.breakTo, 'hh:mm a', new Date()),
        parse(this.breakFrom, 'hh:mm a', new Date())
      );
    },
    totalHours() {
      const dayMinutes = this.timeSlot.openAllDay
        ? 24 * 60
        : differenceInMinutes(this.toDate, this.fromDate);
      const totalMinutes = dayMinutes - this.breakMinutes;
      const [h, m] = [Math.floor(totalMinutes / 60), totalMinutes % 60];

      return [h && `${h}h`, m && `${m}m`].filter(Boolean).join(' ') || '0m';
    },
    hasError() {
      return !this.timeSlot.valid;
    },
    hasBreak: {
      get() {
        return Boolean(this.timeSlot.breakFrom || this.timeSlot.breakTo);
      },
      set(value) {
        const slot = {
          ...this.timeSlot,
          breakFrom: value ? '12:00 PM' : '',
          breakTo: value ? '01:00 PM' : '',
        };
        this.$emit('update', {
          ...slot,
          valid: this.isRangeValid && isBreakValid(slot),
        });
      },
    },
    breakFrom: {
      get() {
        return this.timeSlot.breakFrom;
      },
      set(value) {
        this.updateBreak({ breakFrom: value });
      },
    },
    breakTo: {
      get() {
        return this.timeSlot.breakTo;
      },
      set(value) {
        this.updateBreak({ breakTo: value });
      },
    },
    isRangeValid() {
      if (this.timeSlot.to === '12:00 AM') return true;
      return differenceInMinutes(this.toDate, this.fromDate) > 0;
    },
    hasBreakError() {
      return this.hasBreak && !isBreakValid(this.timeSlot);
    },
    isOpenAllDay: {
      get() {
        return this.timeSlot.openAllDay;
      },
      set(value) {
        const slot = {
          ...this.timeSlot,
          from: value ? '12:00 AM' : '09:00 AM',
          to: value ? '11:59 PM' : '05:00 PM',
          openAllDay: value,
        };
        this.$emit('update', { ...slot, valid: isBreakValid(slot) });
      },
    },
  },
  methods: {
    updateBreak(changes) {
      const slot = { ...this.timeSlot, ...changes };
      this.$emit('update', {
        ...slot,
        valid: this.isRangeValid && isBreakValid(slot),
      });
    },
  },
};
</script>

<template>
  <tr>
    <td class="ltr:pl-4 ltr:pr-3 rtl:pl-3 rtl:pr-4">
      <div class="flex items-center gap-2 min-h-16">
        <input
          v-model="isDayEnabled"
          name="enable-day"
          class="m-0"
          type="checkbox"
          :title="$t('INBOX_MGMT.BUSINESS_HOURS.DAY.ENABLE')"
        />
        <span class="text-body-main text-n-slate-12 font-medium">
          {{ dayName }}
        </span>
      </div>
    </td>
    <td class="py-3 ltr:pr-3 rtl:pl-3">
      <div v-if="isDayEnabled" class="flex flex-col gap-1.5">
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2">
            <input
              v-model="isOpenAllDay"
              name="enable-open-all-day"
              class="m-0"
              type="checkbox"
              :title="$t('INBOX_MGMT.BUSINESS_HOURS.ALL_DAY')"
            />
            <span class="text-body-main text-n-slate-12">{{
              $t('INBOX_MGMT.BUSINESS_HOURS.ALL_DAY')
            }}</span>
          </div>
          <NextSelect
            v-model="fromTime"
            :groups="fromTimeSlots"
            :placeholder="$t('INBOX_MGMT.BUSINESS_HOURS.DAY.CHOOSE')"
            :disabled="isOpenAllDay"
          />
          <div class="flex items-center">
            <Icon icon="i-lucide-minus size-4" />
          </div>
          <NextSelect
            v-model="toTime"
            :groups="toTimeSlots"
            :placeholder="$t('INBOX_MGMT.BUSINESS_HOURS.DAY.CHOOSE')"
            :disabled="isOpenAllDay"
          />
        </div>
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2">
            <input
              v-model="hasBreak"
              name="enable-break"
              class="m-0"
              type="checkbox"
              :title="$t('INBOX_MGMT.BUSINESS_HOURS.BREAK_ENABLE')"
            />
            <span class="text-body-main text-n-slate-12">{{
              $t('INBOX_MGMT.BUSINESS_HOURS.BREAK')
            }}</span>
          </div>
          <template v-if="hasBreak">
            <NextSelect
              v-model="breakFrom"
              :groups="breakTimeSlots"
              :placeholder="$t('INBOX_MGMT.BUSINESS_HOURS.DAY.CHOOSE')"
            />
            <div class="flex items-center">
              <Icon icon="i-lucide-minus size-4" />
            </div>
            <NextSelect
              v-model="breakTo"
              :groups="breakTimeSlots"
              :placeholder="$t('INBOX_MGMT.BUSINESS_HOURS.DAY.CHOOSE')"
            />
          </template>
        </div>
        <span
          v-if="hasError && !hasBreakError"
          class="error text-label-small text-n-ruby-9"
        >
          {{ $t('INBOX_MGMT.BUSINESS_HOURS.DAY.VALIDATION_ERROR') }}
        </span>
        <span v-if="hasBreakError" class="error text-label-small text-n-ruby-9">
          {{ $t('INBOX_MGMT.BUSINESS_HOURS.BREAK_VALIDATION_ERROR') }}
        </span>
      </div>
      <span v-else class="text-body-main text-n-slate-11">
        {{ $t('INBOX_MGMT.BUSINESS_HOURS.DAY.UNAVAILABLE') }}
      </span>
    </td>
    <td class="py-3 ltr:pr-3 rtl:pl-3">
      <span
        v-if="isDayEnabled && !hasError"
        class="label bg-n-blue-3 text-n-blue-11 text-label-small inline-block px-2 py-1 rounded-lg cursor-default whitespace-nowrap"
      >
        {{ totalHours }}
      </span>
    </td>
  </tr>
</template>
