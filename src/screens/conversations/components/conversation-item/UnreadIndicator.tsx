import React from 'react';
import { Text } from 'react-native';

import { tailwind } from '@/theme';
import { NativeView } from '@/components-next/native-components';

type UnreadIndicatorProps = {
  count: number;
};

export const UnreadIndicator = (props: UnreadIndicatorProps) => {
  const { count } = props;

  // A single unread message carries no information a number could add, so it
  // collapses to a bare glyph. `brand-vivid` is only legible as a solid shape.
  if (count <= 1) {
    return <NativeView style={tailwind.style('h-2.5 w-2.5 rounded-full bg-brand-vivid')} />;
  }

  // Once a number sits inside the badge the fill has to carry text contrast,
  // which is what `brand` (not `brand-vivid`) is for.
  return (
    <NativeView
      style={tailwind.style(
        'h-5 min-w-[20px] px-1.5 flex justify-center items-center rounded-full bg-brand',
      )}>
      <Text
        style={tailwind.style(
          'text-xs font-inter-semibold-20 leading-[15px] text-center text-white',
        )}>
        {count > 9 ? '9+' : count}
      </Text>
    </NativeView>
  );
};
