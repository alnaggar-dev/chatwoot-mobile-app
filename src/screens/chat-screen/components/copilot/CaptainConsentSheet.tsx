import React, { forwardRef, useCallback } from 'react';
import { Pressable, Text, View, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { BottomSheetBackdrop, BottomSheetModal, BottomSheetScrollView } from '@gorhom/bottom-sheet';
import type { BottomSheetBackdropProps } from '@gorhom/bottom-sheet';
import * as WebBrowser from 'expo-web-browser';
import { useSelector } from 'react-redux';
import { Button } from '@/components-next';
import { tailwind } from '@/theme';
import { useAppDispatch } from '@/hooks';
import { selectUserId } from '@/store/auth/authSelectors';
import { selectCaptainConsent, selectLocale } from '@/store/settings/settingsSelectors';
import { setCaptainConsent } from '@/store/settings/settingsSlice';
import { resetCopilot } from '@/store/copilot/copilotSlice';
import { PRIVACY_POLICY_URL } from '@/constants/url';
import i18n from '@/i18n';

const BULLET_KEYS = [
  'COPILOT.CONSENT.BULLET_DRAFT',
  'COPILOT.CONSENT.BULLET_CONVERSATION',
  'COPILOT.CONSENT.BULLET_IMPROVE',
  'COPILOT.CONSENT.BULLET_SUGGEST',
] as const;

const BODY_TEXT_STYLE = 'text-[14px] font-inter-normal-20 leading-[20px] text-gray-800';

const renderBackdrop = (props: BottomSheetBackdropProps) => (
  <BottomSheetBackdrop {...props} pressBehavior="none" appearsOnIndex={0} disappearsOnIndex={-1} />
);

type CaptainConsentSheetProps = {
  onAllow?: () => void;
};

export const CaptainConsentSheet = forwardRef<BottomSheetModal, CaptainConsentSheetProps>(
  ({ onAllow }, ref) => {
    const dispatch = useAppDispatch();
    const { bottom } = useSafeAreaInsets();
    const { height: windowHeight } = useWindowDimensions();
    const userId = useSelector(selectUserId);
    const locale = useSelector(selectLocale);
    const hasConsent = useSelector(selectCaptainConsent);

    const dismiss = useCallback(() => {
      if (ref && 'current' in ref && ref.current) {
        ref.current.dismiss();
      }
    }, [ref]);

    const handleAllow = useCallback(() => {
      if (userId === undefined) {
        return;
      }
      dispatch(setCaptainConsent({ userId, allowed: true }));
      dismiss();
      onAllow?.();
    }, [dispatch, dismiss, onAllow, userId]);

    const handleWithdraw = useCallback(() => {
      if (userId !== undefined) {
        dispatch(setCaptainConsent({ userId, allowed: false }));
      }
      dispatch(resetCopilot());
      dismiss();
    }, [dispatch, dismiss, userId]);

    const openPrivacyPolicy = useCallback(async () => {
      await WebBrowser.openBrowserAsync(PRIVACY_POLICY_URL[locale === 'ar' ? 'ar' : 'en']);
    }, [locale]);

    return (
      <BottomSheetModal
        ref={ref}
        backdropComponent={renderBackdrop}
        handleIndicatorStyle={tailwind.style('overflow-hidden bg-blackA-A6 w-8 h-1 rounded-[11px]')}
        handleStyle={tailwind.style('p-0 h-4 pt-[5px]')}
        style={tailwind.style('rounded-t-[26px] overflow-hidden')}
        enablePanDownToClose={false}
        enableDynamicSizing
        maxDynamicContentSize={windowHeight * 0.85}>
        <BottomSheetScrollView
          showsVerticalScrollIndicator={false}
          contentContainerStyle={tailwind.style('px-4', `pb-[${24 + bottom}px]`)}>
          <Text
            style={tailwind.style(
              'text-[17px] font-inter-580-24 leading-[22px] tracking-[0.3px] text-gray-950 pt-1 pb-3',
            )}>
            {i18n.t('COPILOT.CONSENT.TITLE')}
          </Text>
          <Text style={tailwind.style(BODY_TEXT_STYLE, 'pb-2')}>
            {i18n.t('COPILOT.CONSENT.INTRO')}
          </Text>
          {BULLET_KEYS.map(key => (
            <View key={key} style={tailwind.style('flex-row pb-1.5')}>
              <Text style={tailwind.style(BODY_TEXT_STYLE, 'w-4')}>{'\u2022'}</Text>
              <Text style={tailwind.style(BODY_TEXT_STYLE, 'flex-1')}>{i18n.t(key)}</Text>
            </View>
          ))}
          <Text style={tailwind.style(BODY_TEXT_STYLE, 'pt-1 pb-2')}>
            {i18n.t('COPILOT.CONSENT.PURPOSE')}
          </Text>
          <Pressable
            onPress={openPrivacyPolicy}
            accessibilityRole="link"
            style={tailwind.style('self-start pb-4')}>
            <Text style={tailwind.style(BODY_TEXT_STYLE, 'text-brand underline')}>
              {i18n.t('COPILOT.CONSENT.PRIVACY_POLICY')}
            </Text>
          </Pressable>
          <View style={tailwind.style('gap-2')}>
            {hasConsent ? (
              <>
                <Button
                  text={i18n.t('COPILOT.CONSENT.WITHDRAW')}
                  handlePress={handleWithdraw}
                  variant="secondary"
                  isDestructive
                />
                <Button text={i18n.t('COPILOT.CONSENT.CLOSE')} handlePress={dismiss} />
              </>
            ) : (
              <>
                <Button text={i18n.t('COPILOT.CONSENT.ALLOW')} handlePress={handleAllow} />
                <Button
                  text={i18n.t('COPILOT.CONSENT.NOT_NOW')}
                  handlePress={dismiss}
                  variant="secondary"
                />
              </>
            )}
          </View>
        </BottomSheetScrollView>
      </BottomSheetModal>
    );
  },
);
