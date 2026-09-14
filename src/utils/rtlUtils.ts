import { I18nManager, Platform, Settings } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import RNRestart from 'react-native-restart';
import { persistor } from '@/store';

const LAUNCH_RELOAD_KEY = '@foxdesk/rtl-launch-reload';

/** RTL languages available in the app's language list. */
const RTL_LOCALES = ['ar', 'fa', 'he'];

/**
 * iOS fixes the app's language for the whole process at launch, from
 * AppleLanguages filtered by CFBundleLocalizations (app.config.ts), and
 * everything UIKit owns follows that rather than I18nManager: natural text
 * alignment, native menus and alerts, system strings. Pins it to the picked
 * language so the native layer agrees with the JS one. NSBundle caches the
 * choice, so this lands on the next cold start — a JS reload is not enough.
 */
const syncNativeLanguage = (locale: string) => {
  if (Platform.OS !== 'ios') {
    return;
  }
  const language = locale?.split('_')[0]?.toLowerCase();
  const current = Settings.get('AppleLanguages');
  // Entries are BCP 47 ('en-SA', 'zh-Hans-CN'); only the language matters.
  const currentLanguage = Array.isArray(current)
    ? String(current[0] ?? '')
        .split('-')[0]
        .toLowerCase()
    : '';
  if (language && currentLanguage !== language) {
    Settings.set({ AppleLanguages: [language] });
  }
};

// I18nManager.isRTL is captured once when the JS VM starts and goes stale as
// soon as the flags are rewritten, so the direction written in this session is
// tracked here. Comparing against the stale constant let a launch whose flags
// disagreed with the persisted locale leave the two leapfrogging each other on
// every launch, with the pickers never restarting again.
let nativeIsRTL = I18nManager.isRTL;

/**
 * Writes the native layout-direction flags for `locale` when they differ from
 * what the native side currently holds. The flags only take effect on the next
 * launch, so this never restarts by itself. Returns whether a launch is needed.
 */
export const syncRTLDirection = (locale: string): boolean => {
  const shouldBeRTL = RTL_LOCALES.includes(locale?.split('_')[0]?.toLowerCase());
  if (nativeIsRTL === shouldBeRTL) {
    return false;
  }
  I18nManager.allowRTL(shouldBeRTL);
  I18nManager.swapLeftAndRightInRTL(true);
  I18nManager.forceRTL(shouldBeRTL);
  nativeIsRTL = shouldBeRTL;
  return true;
};

/**
 * Call right after `setLocale` was dispatched. Restarts the JS bundle once when
 * the layout direction changed. The redux-persist write is awaited first: the
 * restart tears down the bridge, which drops queued native calls, so a restart
 * issued in the same tick loses the new locale — the app comes back in the old
 * language, flips the direction back and reloads again (a reload storm).
 */
export const restartForLocaleDirection = async (locale: string) => {
  syncNativeLanguage(locale);
  if (!syncRTLDirection(locale)) {
    return;
  }
  await persistor.flush();
  // Falls back to applying on the next manual launch if the native
  // module is missing (binary built before this dependency was added).
  RNRestart?.restart?.();
};

/**
 * Launch only. A direction left disagreeing with the saved language (an
 * interrupted or crashed switch) is repaired with one reload. The reload is
 * bounded, not assumed safe: the flag writes and the bridge reload run on
 * different native queues with no ordering barrier, so a marker is persisted
 * before reloading and a launch that finds it never reloads again — the flags
 * then apply on the next cold start instead of storming.
 */
export const repairLocaleDirectionAtLaunch = async (locale: string) => {
  syncNativeLanguage(locale);
  const reloadedLastLaunch = (await AsyncStorage.getItem(LAUNCH_RELOAD_KEY)) !== null;
  if (reloadedLastLaunch) {
    await AsyncStorage.removeItem(LAUNCH_RELOAD_KEY);
  }
  if (!syncRTLDirection(locale) || reloadedLastLaunch) {
    return;
  }
  await AsyncStorage.setItem(LAUNCH_RELOAD_KEY, locale);
  await persistor.flush();
  RNRestart?.restart?.();
};
