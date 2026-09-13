import React from 'react';
import Animated from 'react-native-reanimated';

import i18n from 'i18n';
import { tailwind } from '@/theme';

export const SettingsHeader = () => {
  return (
    <Animated.View style={tailwind.style('px-4 pt-4 pb-3 border-b-[1px] border-b-blackA-A3')}>
      {/* left = start: RN flips it under RTL, natural alignment on iOS does not */}
      <Animated.Text
        numberOfLines={1}
        style={tailwind.style('text-3xl font-inter-semibold-20 text-ink text-left')}>
        {i18n.t('SETTINGS.HEADER_TITLE')}
      </Animated.Text>
    </Animated.View>
  );
};
