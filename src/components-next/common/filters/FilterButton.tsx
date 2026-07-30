import React, { useCallback } from 'react';
import { Pressable } from 'react-native';
import Animated from 'react-native-reanimated';

import { useRefsContext } from '@/context';

import { CaretBottomSmall } from '@/svg-icons';
import { tailwind } from '@/theme';
import { useHaptic, useScaleAnimation } from '@/utils';
import { Icon } from '../icon';

type FilterButtonProps = {
  value: string;
  isActive?: boolean;
  handleOnPress: () => void;
};

export const FilterButton = (props: FilterButtonProps) => {
  const { value, isActive = false, handleOnPress } = props;
  const { handlers, animatedStyle } = useScaleAnimation();
  const { filtersModalSheetRef } = useRefsContext();

  const hapticSelection = useHaptic();

  const onPress = useCallback(() => {
    hapticSelection?.();
    filtersModalSheetRef.current?.present();
    handleOnPress();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <Animated.View style={[animatedStyle, tailwind.style('min-h-[44px] justify-center')]}>
      <Pressable
        hitSlop={{ top: 7, bottom: 7 }}
        style={tailwind.style(
          'px-3 py-1.5 rounded-full border flex flex-row items-center',
          isActive ? 'bg-brand-subtle border-brand-muted' : 'bg-surface-subtle border-outline-soft',
        )}
        onPress={onPress}
        {...handlers}>
        <Animated.Text
          style={tailwind.style(
            'text-cxs leading-[16px] tracking-[0.24px] pr-1 capitalize',
            isActive
              ? 'font-inter-semibold-20 text-brand'
              : 'font-inter-medium-24 text-ink-secondary',
          )}>
          {value}
        </Animated.Text>
        <Icon
          icon={<CaretBottomSmall fill={tailwind.color('text-ink-muted') as string} />}
          size={7.5}
        />
      </Pressable>
    </Animated.View>
  );
};
