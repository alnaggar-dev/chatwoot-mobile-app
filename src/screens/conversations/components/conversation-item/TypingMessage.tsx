import React from 'react';
import { Text } from 'react-native';

import { tailwind } from '@/theme';
import { NativeView } from '@/components-next/native-components';

type TypingMessageProps = {
  typingText: string;
};

export const TypingMessage = (props: TypingMessageProps) => {
  const { typingText } = props;
  return (
    <NativeView style={tailwind.style('flex-1 flex-row gap-1 items-center')}>
      <Text
        numberOfLines={1}
        style={tailwind.style('text-md flex-1 font-inter-medium-24 leading-[20px] text-brand')}>
        {typingText}
      </Text>
    </NativeView>
  );
};
