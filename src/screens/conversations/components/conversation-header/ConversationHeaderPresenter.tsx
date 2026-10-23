import React from 'react';
import { Pressable, Text, ViewStyle } from 'react-native';
import Animated, {
  AnimatedStyle,
  useAnimatedStyle,
  useDerivedValue,
  withDelay,
  withTiming,
} from 'react-native-reanimated';
import { Icon } from '@/components-next/common';
import { CheckedIcon, CloseIcon, FilterIcon, UncheckedIcon, SearchIcon } from '@/svg-icons';
import { tailwind } from '@/theme';
import i18n from '@/i18n';
import { useScaleAnimation } from '@/utils';
import { useHeaderAnimation } from '@/hooks/useHeaderAnimation';

type HeaderState = 'Search' | 'Filter' | 'Select' | 'none';

type ConversationHeaderPresenterProps = {
  currentState: HeaderState;
  isSelectedAll: boolean;
  filtersAppliedCount: number;
  onLeftIconPress: () => void;
  onRightIconPress: () => void;
  onClearFilter: () => void;
};

type ActionSlotProps = {
  currentState: HeaderState;
  isSelectedAll: boolean;
  filtersAppliedCount: number;
  onLeftIconPress: () => void;
  onClearFilter: () => void;
  handlers: Record<string, unknown>;
  animatedStyle: ViewStyle | AnimatedStyle<ViewStyle>;
};

type FilterOrCloseActionProps = {
  currentState: HeaderState;
  filtersAppliedCount: number;
  onRightIconPress: () => void;
};

const CROSSFADE_MS = 180;

// The active action stays in the layout and sizes the slot; inactive ones sit on top of it at
// the end edge while they fade out, so swapping never shifts the actions next to it.
const layerStyle = (active: boolean) =>
  active
    ? tailwind.style('flex-row items-center')
    : [tailwind.style('absolute top-0 bottom-0 flex-row items-center'), { end: 0 }];

const ActionSlot = ({
  currentState,
  isSelectedAll,
  filtersAppliedCount,
  onLeftIconPress,
  onClearFilter,
  handlers,
  animatedStyle,
}: ActionSlotProps) => {
  const searchActive = currentState === 'none';
  const clearActive = currentState === 'Filter';
  const selectActive = currentState === 'Select';

  const searchOpacity = useDerivedValue(
    () =>
      withDelay(
        searchActive ? CROSSFADE_MS : 0,
        withTiming(searchActive ? 1 : 0, { duration: CROSSFADE_MS }),
      ),
    [searchActive],
  );
  const clearOpacity = useDerivedValue(
    () =>
      withDelay(
        clearActive ? CROSSFADE_MS : 0,
        withTiming(clearActive ? 1 : 0, { duration: CROSSFADE_MS }),
      ),
    [clearActive],
  );
  const selectOpacity = useDerivedValue(
    () =>
      withDelay(
        selectActive ? CROSSFADE_MS : 0,
        withTiming(selectActive ? 1 : 0, { duration: CROSSFADE_MS }),
      ),
    [selectActive],
  );

  const searchStyle = useAnimatedStyle(() => ({ opacity: searchOpacity.value }));
  const clearStyle = useAnimatedStyle(() => ({ opacity: clearOpacity.value }));
  const selectStyle = useAnimatedStyle(() => ({ opacity: selectOpacity.value }));

  return (
    <Animated.View style={tailwind.style('h-6 flex-row items-center')}>
      <Animated.View
        style={[layerStyle(clearActive), clearStyle]}
        pointerEvents={clearActive ? 'auto' : 'none'}>
        <Pressable onPress={onClearFilter} disabled={filtersAppliedCount === 0} {...handlers}>
          <Animated.View style={animatedStyle}>
            <Text
              style={tailwind.style(
                'text-md font-inter-medium-24 leading-[17px] tracking-[0.24px]',
                filtersAppliedCount === 0 ? 'text-ink-muted' : 'text-brand',
              )}>
              {i18n.t('CONVERSATION.HEADER.CLEAR_FILTER')}
              {filtersAppliedCount > 0 ? ` (${filtersAppliedCount})` : ''}
            </Text>
          </Animated.View>
        </Pressable>
      </Animated.View>

      <Animated.View
        style={[layerStyle(searchActive), searchStyle]}
        pointerEvents={searchActive ? 'auto' : 'none'}>
        <Pressable onPress={onLeftIconPress} hitSlop={16}>
          <Icon size={24} icon={<SearchIcon stroke={tailwind.color('text-ink-secondary')} />} />
        </Pressable>
      </Animated.View>

      <Animated.View
        style={[layerStyle(selectActive), selectStyle]}
        pointerEvents={selectActive ? 'auto' : 'none'}>
        <Pressable onPress={onLeftIconPress} hitSlop={16}>
          <Icon
            size={24}
            icon={
              isSelectedAll ? (
                <CheckedIcon />
              ) : (
                <UncheckedIcon stroke={tailwind.color('text-ink-secondary')} />
              )
            }
          />
        </Pressable>
      </Animated.View>
    </Animated.View>
  );
};

const FilterOrCloseAction = ({
  currentState,
  filtersAppliedCount,
  onRightIconPress,
}: FilterOrCloseActionProps) => {
  const { entering, exiting } = useHeaderAnimation();

  return (
    <Pressable onPress={onRightIconPress} hitSlop={16}>
      {currentState === 'Filter' || currentState === 'Select' ? (
        <Animated.View exiting={exiting} entering={entering}>
          <Icon size={24} icon={<CloseIcon />} />
        </Animated.View>
      ) : (
        <Animated.View exiting={exiting} entering={entering}>
          {filtersAppliedCount > 0 && (
            <Animated.View
              style={tailwind.style(
                'absolute z-10 -right-0.5 h-2.5 w-2.5 rounded-full bg-brand-vivid',
              )}
            />
          )}
          <Icon size={24} icon={<FilterIcon />} />
        </Animated.View>
      )}
    </Pressable>
  );
};

export const ConversationHeaderPresenter = ({
  currentState,
  isSelectedAll,
  filtersAppliedCount,
  onLeftIconPress,
  onRightIconPress,
  onClearFilter,
}: ConversationHeaderPresenterProps) => {
  const { handlers, animatedStyle } = useScaleAnimation();

  return (
    <Animated.View style={tailwind.style('px-4 pt-4 pb-3')}>
      <Animated.View style={tailwind.style('flex flex-row items-center justify-between gap-4')}>
        {/* left = start: RN flips it under RTL, natural alignment on iOS does not */}
        <Text
          numberOfLines={1}
          style={tailwind.style('flex-1 text-3xl font-inter-semibold-20 text-ink text-left')}>
          {i18n.t('CONVERSATION.HEADER.TITLE')}
        </Text>
        <Animated.View style={tailwind.style('flex flex-row items-center gap-5')}>
          <ActionSlot
            currentState={currentState}
            isSelectedAll={isSelectedAll}
            filtersAppliedCount={filtersAppliedCount}
            onLeftIconPress={onLeftIconPress}
            onClearFilter={onClearFilter}
            handlers={handlers}
            animatedStyle={animatedStyle}
          />
          <FilterOrCloseAction
            currentState={currentState}
            filtersAppliedCount={filtersAppliedCount}
            onRightIconPress={onRightIconPress}
          />
        </Animated.View>
      </Animated.View>
    </Animated.View>
  );
};
