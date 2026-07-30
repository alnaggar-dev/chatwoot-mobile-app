import React from 'react';
import { Pressable } from 'react-native';
import Animated from 'react-native-reanimated';

import { useRefsContext } from '@/context';
import { tailwind } from '@/theme';
import { SortTypes } from '@/types';
import { useHaptic } from '@/utils';
import { BottomSheetHeader } from '@/components-next';
import { useAppDispatch, useAppSelector } from '@/hooks';
import i18n from '@/i18n';
import { SortOptions } from '@/types';
import { selectFilters, setFilters } from '@/store/conversation/conversationFilterSlice';

type SortByCellProps = {
  value: string;
};

const sortByList = Object.keys(SortOptions) as SortTypes[];

const SortByCell = (props: SortByCellProps) => {
  const { filtersModalSheetRef } = useRefsContext();
  const { value } = props;
  const filters = useAppSelector(selectFilters);
  const dispatch = useAppDispatch();

  const hapticSelection = useHaptic();

  const isActive = filters.sort_by === value;

  const handlePreferredSortPress = () => {
    hapticSelection?.();
    dispatch(setFilters({ key: 'sort_by', value }));
    setTimeout(() => filtersModalSheetRef.current?.dismiss({ overshootClamping: true }), 1);
  };

  return (
    <Pressable
      style={tailwind.style('min-h-[44px] justify-center')}
      onPress={handlePreferredSortPress}>
      <Animated.View
        style={tailwind.style(
          'flex flex-row items-center py-1.5 px-3 rounded-full border',
          isActive ? 'bg-brand-subtle border-brand-muted' : 'bg-surface-subtle border-outline-soft',
        )}>
        <Animated.Text
          style={tailwind.style(
            'text-cxs leading-[16px] tracking-[0.24px] capitalize',
            isActive
              ? 'font-inter-semibold-20 text-brand'
              : 'font-inter-medium-24 text-ink-secondary',
          )}>
          {i18n.t(`CONVERSATION.FILTERS.SORT_BY.OPTIONS.${value.toUpperCase()}`)}
        </Animated.Text>
      </Animated.View>
    </Pressable>
  );
};

type SortByStackProps = {
  list: SortTypes[];
};

const SortByStack = (props: SortByStackProps) => {
  const { list } = props;
  return (
    <Animated.View style={tailwind.style('flex flex-row flex-wrap gap-2 px-4 pt-1 pb-4')}>
      {list.map((value, index) => (
        <SortByCell key={index} {...{ value }} />
      ))}
    </Animated.View>
  );
};

export const SortByFilters = () => {
  return (
    <Animated.View>
      <BottomSheetHeader headerText={i18n.t('CONVERSATION.FILTERS.SORT_BY.TITLE')} />
      <SortByStack list={sortByList} />
    </Animated.View>
  );
};
