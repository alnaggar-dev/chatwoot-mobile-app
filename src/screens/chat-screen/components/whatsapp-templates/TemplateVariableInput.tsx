import React from 'react';
import { I18nManager, View } from 'react-native';
import Animated from 'react-native-reanimated';
import { BottomSheetTextInput } from '@gorhom/bottom-sheet';

import { tailwind } from '@/theme';

type TemplateVariableInputProps = {
  label: string;
  value: string;
  onChangeText: (value: string) => void;
  isFocused: boolean;
  onFocus: () => void;
  onBlur: () => void;
};

const TemplateVariableInput = ({
  label,
  value,
  onChangeText,
  isFocused,
  onFocus,
  onBlur,
}: TemplateVariableInputProps) => (
  <View style={tailwind.style('flex-row items-center mb-4')}>
    <Animated.Text
      style={tailwind.style(
        'w-8 text-[15px] font-inter-medium-24 tracking-[0.225px] text-ink-muted',
      )}>
      {label}
    </Animated.Text>
    <BottomSheetTextInput
      value={value}
      onChangeText={onChangeText}
      onFocus={onFocus}
      onBlur={onBlur}
      autoCapitalize="none"
      autoCorrect={false}
      placeholder={label}
      placeholderTextColor={tailwind.color('text-ink-muted')}
      style={tailwind.style(
        'flex-1 px-3 py-2 rounded-control border text-base font-inter-420-20 text-ink',
        I18nManager.isRTL && 'text-right',
        isFocused ? 'border-brand' : 'border-outline',
      )}
    />
  </View>
);

export default TemplateVariableInput;
