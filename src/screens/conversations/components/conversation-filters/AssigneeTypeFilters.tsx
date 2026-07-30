import React from 'react';
import { Pressable } from 'react-native';
import Animated from 'react-native-reanimated';

import { useRefsContext } from '@/context';
import { tailwind } from '@/theme';
import { AssigneeTypes } from '@/types';
import { useHaptic } from '@/utils';
import { BottomSheetHeader } from '@/components-next';
import { selectFilters, setFilters } from '@/store/conversation/conversationFilterSlice';
import { useAppDispatch, useAppSelector } from '@/hooks';
import i18n from '@/i18n';
import { AssigneeOptions } from '@/types';
import { useSelector } from 'react-redux';
import { selectUser } from '@/store/auth/authSelectors';
import { getUserPermissions } from '@/utils/permissionUtils';

type AssigneeTypeCellProps = {
  value: string;
};

const assigneeTypeList = Object.keys(AssigneeOptions) as AssigneeTypes[];

const AssigneeTypeCell = (props: AssigneeTypeCellProps) => {
  const { filtersModalSheetRef } = useRefsContext();
  const { value } = props;
  const dispatch = useAppDispatch();
  const filters = useAppSelector(selectFilters);
  const hapticSelection = useHaptic();

  const isActive = filters.assignee_type === value;

  const handlePreferredAssigneeTypePress = () => {
    hapticSelection?.();
    dispatch(setFilters({ key: 'assignee_type', value }));
    setTimeout(() => filtersModalSheetRef.current?.dismiss({ overshootClamping: true }), 1);
  };

  return (
    <Pressable
      style={tailwind.style('min-h-[44px] justify-center')}
      onPress={handlePreferredAssigneeTypePress}>
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
          {i18n.t(`CONVERSATION.FILTERS.ASSIGNEE_TYPE.OPTIONS.${value.toUpperCase()}`)}
        </Animated.Text>
      </Animated.View>
    </Pressable>
  );
};

export const AssigneeTypeFilters = () => {
  const user = useSelector(selectUser);
  const { account_id: activeAccountId } = user || { account_id: null };

  const userPermissions = user ? getUserPermissions(user, activeAccountId) : [];

  // If userPermissions contains any values conversation_manage_permission,administrator, agent then keep all the assignee types
  // If conversation_manage is not available and conversation_unassigned_manage only is available, then return only unassigned and mine
  // If conversation_manage is not available and conversation_participating_manage only is available, then return only all and mine
  let assigneeTypes = assigneeTypeList;

  if (
    userPermissions.includes('conversation_manage') ||
    userPermissions.includes('agent') ||
    userPermissions.includes('administrator')
  ) {
    // Keep all the assignee types
  } else if (userPermissions.includes('conversation_unassigned_manage')) {
    assigneeTypes = assigneeTypeList.filter(type => type !== 'all');
  } else {
    assigneeTypes = assigneeTypeList.filter(type => type !== 'unassigned');
  }
  return (
    <Animated.View>
      <BottomSheetHeader headerText={i18n.t('CONVERSATION.FILTERS.ASSIGNEE_TYPE.TITLE')} />
      <Animated.View style={tailwind.style('flex flex-row flex-wrap gap-2 px-4 pt-1 pb-4')}>
        {assigneeTypes.map((value, index) => (
          <AssigneeTypeCell key={index} {...{ value }} />
        ))}
      </Animated.View>
    </Animated.View>
  );
};
