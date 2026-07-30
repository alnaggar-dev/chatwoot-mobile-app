import React from 'react';
import { StatusBar, Pressable } from 'react-native';
import Animated from 'react-native-reanimated';

import { SearchBar } from '@/components-next/common/search';
import { Icon } from '@/components-next';
import { ChevronLeft } from '@/svg-icons';
import { tailwind } from '@/theme';
import i18n from 'i18n';

interface SearchHeaderProps {
  searchText: string;
  isLoading: boolean;
  onSearchChange: (text: string) => void;
  onClear: () => void;
  onBackPress: () => void;
}

export function SearchHeader({
  searchText,
  isLoading,
  onSearchChange,
  onClear,
  onBackPress,
}: SearchHeaderProps) {
  return (
    <>
      <StatusBar
        translucent
        backgroundColor={tailwind.color('bg-surface')}
        barStyle={'dark-content'}
      />
      <Animated.View style={tailwind.style('pt-2 pb-3 border-b-[1px] border-b-blackA-A3')}>
        <Animated.View style={tailwind.style('flex flex-row items-center px-4')}>
          <Pressable
            hitSlop={16}
            style={tailwind.style('h-8 w-8 flex justify-center items-start')}
            onPress={onBackPress}>
            <Icon icon={<ChevronLeft />} size={24} />
          </Pressable>
        </Animated.View>
        <Animated.Text
          numberOfLines={1}
          style={tailwind.style('px-4 pt-1 text-3xl font-inter-semibold-20 text-ink')}>
          {i18n.t('SEARCH.TITLE')}
        </Animated.Text>
        {/* SearchBar carries its own px-3, so px-1 lands the field on the px-4 grid. */}
        <Animated.View style={tailwind.style('px-1 pt-3')}>
          <SearchBar
            placeholder={i18n.t('SEARCH.PLACEHOLDER')}
            autoFocus
            value={searchText}
            onChangeText={onSearchChange}
            isLoading={isLoading}
            onClear={onClear}
          />
        </Animated.View>
      </Animated.View>
    </>
  );
}
