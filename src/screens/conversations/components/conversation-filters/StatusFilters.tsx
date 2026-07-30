import React from 'react';
import { Pressable } from 'react-native';
import Animated from 'react-native-reanimated';
import { BottomSheetView } from '@gorhom/bottom-sheet';

import { useRefsContext } from '@/context';
import { selectFilters, setFilters } from '@/store/conversation/conversationFilterSlice';
import { tailwind } from '@/theme';
import { AllStatusTypes } from '@/types';
import { useHaptic } from '@/utils';
import { BottomSheetHeader } from '@/components-next';
import { useAppDispatch, useAppSelector } from '@/hooks';
import i18n from '@/i18n';
import { StatusOptions } from '@/types';

type StatusCellProps = {
  value: AllStatusTypes;
};

export const status: AllStatusTypes[] = ['all', 'open', 'pending', 'snoozed', 'resolved'];

// The dot carries the status hue; "all" is not a status, so it stays label-only.
const statusDotStyle: Partial<Record<AllStatusTypes, string>> = {
  open: 'bg-status-open',
  pending: 'bg-status-pending',
  snoozed: 'bg-status-snoozed',
  resolved: 'bg-status-resolved',
};

const StatusCell = (props: StatusCellProps) => {
  const { filtersModalSheetRef } = useRefsContext();
  const { value } = props;
  const filters = useAppSelector(selectFilters);
  const dispatch = useAppDispatch();
  const hapticSelection = useHaptic();

  const isActive = filters.status === value;
  const dotStyle = statusDotStyle[value];

  const handleStatusPress = () => {
    hapticSelection?.();
    dispatch(setFilters({ key: 'status', value }));
    setTimeout(() => filtersModalSheetRef.current?.dismiss({ overshootClamping: true }), 1);
  };

  return (
    <Pressable style={tailwind.style('min-h-[44px] justify-center')} onPress={handleStatusPress}>
      <Animated.View
        style={tailwind.style(
          'flex flex-row items-center py-1.5 px-3 rounded-full border',
          isActive ? 'bg-brand-subtle border-brand-muted' : 'bg-surface-subtle border-outline-soft',
        )}>
        {dotStyle ? (
          <Animated.View style={tailwind.style('h-1.5 w-1.5 rounded-full mr-1.5', dotStyle)} />
        ) : null}
        <Animated.Text
          style={tailwind.style(
            'text-cxs leading-[16px] tracking-[0.24px] capitalize',
            isActive
              ? 'font-inter-semibold-20 text-brand'
              : 'font-inter-medium-24 text-ink-secondary',
          )}>
          {i18n.t(`CONVERSATION.FILTERS.STATUS.OPTIONS.${StatusOptions[value].toUpperCase()}`)}
        </Animated.Text>
      </Animated.View>
    </Pressable>
  );
};

type StatusStackProps = {
  statusList: AllStatusTypes[];
};

const StatusStack = (props: StatusStackProps) => {
  const { statusList } = props;
  return (
    <Animated.View style={tailwind.style('flex flex-row flex-wrap gap-2 px-4 pt-1 pb-4')}>
      {statusList.map((value, index) => (
        <StatusCell key={index} {...{ value }} />
      ))}
    </Animated.View>
  );
};

export const StatusFilters = () => {
  return (
    <BottomSheetView>
      <BottomSheetHeader headerText={i18n.t('CONVERSATION.FILTERS.STATUS.TITLE')} />
      <StatusStack statusList={status} />
    </BottomSheetView>
  );
};
