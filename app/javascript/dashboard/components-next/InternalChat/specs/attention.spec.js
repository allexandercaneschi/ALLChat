import { blinkTitle, showDesktopNotification } from '../attention';

describe('InternalChat attention', () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  describe('blinkTitle', () => {
    it('alternates the tab title and restores it when the agent comes back', () => {
      vi.useFakeTimers();
      document.title = 'ALL Chat';

      blinkTitle('Ana is calling your attention');
      vi.advanceTimersByTime(800);
      expect(document.title).toBe('Ana is calling your attention');
      vi.advanceTimersByTime(800);
      expect(document.title).toBe('ALL Chat');
      vi.advanceTimersByTime(800);
      expect(document.title).toBe('Ana is calling your attention');

      window.dispatchEvent(new Event('focus'));
      expect(document.title).toBe('ALL Chat');
      vi.advanceTimersByTime(5000);
      expect(document.title).toBe('ALL Chat');
    });

    it('stops by itself after a while', () => {
      vi.useFakeTimers();
      document.title = 'ALL Chat';

      blinkTitle('alert');
      vi.advanceTimersByTime(61000);

      expect(document.title).toBe('ALL Chat');
    });
  });

  describe('showDesktopNotification', () => {
    it('keeps the notification on screen until dismissed', () => {
      const notification = vi.fn();
      notification.permission = 'granted';
      vi.stubGlobal('Notification', notification);

      showDesktopNotification({ title: 'Ana', body: 'oi', tag: 't' });

      expect(notification).toHaveBeenCalledWith('Ana', {
        body: 'oi',
        tag: 't',
        requireInteraction: true,
      });
    });

    it('does nothing without permission', () => {
      const notification = vi.fn();
      notification.permission = 'denied';
      vi.stubGlobal('Notification', notification);

      showDesktopNotification({ title: 'Ana', body: 'oi', tag: 't' });

      expect(notification).not.toHaveBeenCalled();
    });
  });
});
