import React from 'react';
import { Pressable } from 'react-native';
import Animated from 'react-native-reanimated';

import { useRefsContext } from '@/context';
import { tailwind } from '@/theme';
import { useHaptic } from '@/utils';
import { BottomSheetHeader } from '@/components-next';
import i18n from '@/i18n';
import { InboxSortTypes, InboxSortOptions } from '@/store/notification/notificationTypes';
import { selectSortOrder, setFilters } from '@/store/notification/notificationFilterSlice';
import { useAppDispatch, useAppSelector } from '@/hooks';

type SortByCellProps = {
  value: string;
  onChange: (value: InboxSortTypes) => void;
  sortOrder: InboxSortTypes;
};

const sortByList = Object.keys(InboxSortOptions) as InboxSortTypes[];

const SortByCell = (props: SortByCellProps) => {
  const { value, sortOrder, onChange } = props;

  const hapticSelection = useHaptic();

  const isActive = sortOrder === value;

  const handlePreferredSortPress = () => {
    hapticSelection?.();
    onChange(value as InboxSortTypes);
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
          {i18n.t(`NOTIFICATION.FILTERS.SORT_BY.OPTIONS.${value.toUpperCase()}`)}
        </Animated.Text>
      </Animated.View>
    </Pressable>
  );
};

export const InboxFilters = () => {
  const sortOrder = useAppSelector(selectSortOrder);
  const dispatch = useAppDispatch();
  const { inboxFiltersSheetRef } = useRefsContext();

  const handleChangeFilters = (value: InboxSortTypes) => {
    dispatch(setFilters({ key: value }));
    setTimeout(() => inboxFiltersSheetRef.current?.dismiss({ overshootClamping: true }), 1);
  };

  return (
    <Animated.View>
      <BottomSheetHeader headerText={i18n.t('CONVERSATION.FILTERS.SORT_BY.TITLE')} />
      <Animated.View style={tailwind.style('flex flex-row flex-wrap gap-2 px-4 pt-1 pb-4')}>
        {sortByList.map((value, index) => (
          <SortByCell
            key={index}
            {...{ value }}
            sortOrder={sortOrder}
            onChange={handleChangeFilters}
          />
        ))}
      </Animated.View>
    </Animated.View>
  );
};
