import React from 'react';
import { Text } from 'react-native';

import { tailwind } from '@/theme';

type ConversationIdProps = {
  id: number;
};

export const ConversationId = (props: ConversationIdProps) => {
  const { id } = props;
  return (
    <Text style={tailwind.style('text-xs font-inter-normal-20 text-ink-muted')}>{`#${id}`}</Text>
  );
};

ConversationId.displayName = 'ConversationId';
