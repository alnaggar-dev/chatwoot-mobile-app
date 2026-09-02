import { I18nManager } from 'react-native';
import RNRestart from 'react-native-restart';

/** RTL languages available in the app's language list. */
const RTL_LOCALES = ['ar', 'fa', 'he'];

/**
 * Keeps the native layout direction in sync with the app language.
 * `forceRTL`/`swapLeftAndRightInRTL` persist natively and only apply on
 * the next launch, so the app is restarted once when either changes.
 */
export const syncRTLDirection = (locale: string) => {
  const shouldBeRTL = RTL_LOCALES.includes(locale?.split('_')[0]?.toLowerCase());
  // iOS defaults doLeftAndRightSwapInRTL to false (unregistered NSUserDefaults
  // key), so physical left/right styles would not mirror even with isRTL set.
  const needsSwapFlag = shouldBeRTL && !I18nManager.doLeftAndRightSwapInRTL;
  if (I18nManager.isRTL === shouldBeRTL && !needsSwapFlag) {
    return;
  }
  I18nManager.allowRTL(shouldBeRTL);
  I18nManager.swapLeftAndRightInRTL(true);
  I18nManager.forceRTL(shouldBeRTL);
  // Falls back to applying on the next manual launch if the native
  // module is missing (binary built before this dependency was added).
  RNRestart?.restart?.();
};
