// Ways to call the attention of the agent on the computer: a tone, a blinking tab title and a desktop
// notification that stays on screen until it is dismissed. The phone gets an urgent push from the server.
const TONE_FREQUENCIES = [880, 660, 880];
const TONE_STEP_SECONDS = 0.18;
const TITLE_BLINK_INTERVAL_MS = 800;
const TITLE_BLINK_MAX_MS = 60000;

export const playAttentionTone = () => {
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  if (!AudioContextClass) return;
  const context = new AudioContextClass();
  TONE_FREQUENCIES.forEach((frequency, index) => {
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.frequency.value = frequency;
    gain.gain.value = 0.2;
    oscillator.connect(gain);
    gain.connect(context.destination);
    oscillator.start(context.currentTime + index * TONE_STEP_SECONDS);
    oscillator.stop(
      context.currentTime + index * TONE_STEP_SECONDS + TONE_STEP_SECONDS * 0.8
    );
  });
  setTimeout(
    () => context.close(),
    TONE_FREQUENCIES.length * TONE_STEP_SECONDS * 1000 + 200
  );
};

// Alternates the tab title with the alert text until the agent comes back to the tab.
// Returns a function that stops it.
export const blinkTitle = text => {
  const originalTitle = document.title;
  let showAlert = true;
  const timers = {};
  const stop = () => {
    clearInterval(timers.blink);
    clearTimeout(timers.limit);
    window.removeEventListener('focus', stop);
    document.title = originalTitle;
  };
  timers.blink = setInterval(() => {
    document.title = showAlert ? text : originalTitle;
    showAlert = !showAlert;
  }, TITLE_BLINK_INTERVAL_MS);
  timers.limit = setTimeout(stop, TITLE_BLINK_MAX_MS);
  window.addEventListener('focus', stop);
  return stop;
};

export const showDesktopNotification = ({ title, body, tag }) => {
  if (typeof Notification === 'undefined') return;
  if (Notification.permission !== 'granted') return;
  // requireInteraction keeps it on screen until the agent dismisses it.
  // eslint-disable-next-line no-new
  new Notification(title, { body, tag, requireInteraction: true });
};

export const callAttention = ({ title, body, tag }) => {
  playAttentionTone();
  blinkTitle(title);
  showDesktopNotification({ title, body, tag });
};
