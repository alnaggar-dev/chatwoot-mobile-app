/* eslint-disable react/display-name */
import React, { Fragment, memo, useState } from 'react';
import { ImageURISource, Text } from 'react-native';
import { LinearTransition } from 'react-native-reanimated';
import { isEqual } from 'lodash';

import { Avatar } from '@/components-next/common';
import { AnimatedNativeView, NativeView } from '@/components-next/native-components';
import { tailwind } from '@/theme';
import { Agent, Conversation, ConversationAdditionalAttributes, Label, Message } from '@/types';

import { ConversationId } from './ConversationId';
import { ConversationLastMessage } from './ConversationLastMessage';
import { PriorityIndicator, ChannelIndicator } from '@/components-next/list-components';
import { UnreadIndicator } from './UnreadIndicator';
import { SLAIndicator } from './SLAIndicator';
import { LabelIndicator } from './LabelIndicator';
import { LastActivityTime } from './LastActivityTime';
import { SLA } from '@/types/common/SLA';
import { Inbox } from '@/types/Inbox';
import { TypingMessage } from './TypingMessage';

type ConversationDetailSubCellProps = Pick<
  Conversation,
  'id' | 'priority' | 'labels' | 'unreadCount' | 'inboxId' | 'slaPolicyId'
> & {
  senderName: string | null;
  assignee: Agent | null;
  timestamp: number;
  lastMessage?: Message | null;
  inbox: Inbox | null;
  appliedSla: SLA | null;
  appliedSlaConversationDetails?:
    | {
        firstReplyCreatedAt: number;
        waitingSince: number;
        status: string;
      }
    | Record<string, never>;
  additionalAttributes?: ConversationAdditionalAttributes;
  allLabels: Label[];
  typingText?: string;
};

const checkIfPropsAreSame = (
  prev: ConversationDetailSubCellProps,
  next: ConversationDetailSubCellProps,
) => {
  const arePropsEqual = isEqual(prev, next);
  return arePropsEqual;
};

export const ConversationItemDetail = memo((props: ConversationDetailSubCellProps) => {
  const {
    id: conversationId,
    priority,
    unreadCount,
    labels,
    assignee,
    senderName,
    timestamp,
    slaPolicyId,
    lastMessage,
    inbox,
    appliedSla,
    appliedSlaConversationDetails,
    additionalAttributes,
    allLabels,
    typingText,
  } = props;

  const [shouldShowSLA, setShouldShowSLA] = useState(true);

  const hasPriority = priority !== null;

  const hasLabels = labels.length > 0;

  const hasSLA = !!slaPolicyId && shouldShowSLA;

  const isUnread = unreadCount >= 1;

  if (!lastMessage) {
    return null;
  }

  // Every annotation that used to compete with the sender name and the preview
  // collapses into a single quiet tier, anchored by the conversation id.
  const metaItems = [
    <ConversationId key="id" id={conversationId} />,
    hasPriority ? <PriorityIndicator key="priority" {...{ priority }} /> : null,
    hasLabels ? <LabelIndicator key="labels" labels={labels} allLabels={allLabels} /> : null,
    inbox ? (
      <ChannelIndicator key="channel" inbox={inbox} additionalAttributes={additionalAttributes} />
    ) : null,
    hasSLA ? (
      <SLAIndicator
        key="sla"
        slaPolicyId={slaPolicyId}
        appliedSla={appliedSla as SLA}
        appliedSlaConversationDetails={
          appliedSlaConversationDetails as {
            firstReplyCreatedAt: number;
            waitingSince: number;
            status: string;
          }
        }
        onSLAStatusChange={setShouldShowSLA}
      />
    ) : null,
  ].filter((item): item is React.ReactElement => item !== null);

  // The preview earns a second line only when nothing but the id shares the
  // meta tier with it, which keeps the row height stable down the list.
  const previewLines = metaItems.length > 1 ? 1 : 2;

  return (
    <AnimatedNativeView
      layout={LinearTransition.springify().damping(28).stiffness(200)}
      style={tailwind.style('flex-1 gap-0.5 py-2 border-b-[1px] border-b-blackA-A3')}>
      <AnimatedNativeView style={tailwind.style('flex-row items-center gap-2 min-h-[20px]')}>
        <Text
          numberOfLines={1}
          style={tailwind.style(
            'flex-1 min-w-0 text-base leading-5 font-inter-semibold-20 text-ink capitalize',
          )}>
          {senderName}
        </Text>
        <LastActivityTime timestamp={timestamp} />
      </AnimatedNativeView>

      <AnimatedNativeView style={tailwind.style('flex-row items-center gap-2 min-h-[20px]')}>
        {typingText ? (
          <TypingMessage typingText={typingText} />
        ) : (
          <ConversationLastMessage
            numberOfLines={previewLines}
            lastMessage={lastMessage as Message}
            isUnread={isUnread}
          />
        )}

        {isUnread && (
          <NativeView style={tailwind.style('flex-shrink-0')}>
            <UnreadIndicator count={unreadCount} />
          </NativeView>
        )}
      </AnimatedNativeView>

      <AnimatedNativeView
        style={tailwind.style('flex-row items-center justify-between gap-2 min-h-[20px]')}>
        <AnimatedNativeView
          style={tailwind.style('flex-1 flex-row items-center gap-1 overflow-hidden')}>
          {metaItems.map((item, index) => (
            <Fragment key={item.key}>
              {index > 0 && (
                <Text style={tailwind.style('text-xs font-inter-normal-20 text-ink-muted')}>
                  {'\u00B7'}
                </Text>
              )}
              {item}
            </Fragment>
          ))}
        </AnimatedNativeView>

        {assignee ? (
          <Avatar
            size="sm"
            name={assignee.name as string}
            src={{ uri: assignee.thumbnail } as ImageURISource}
          />
        ) : null}
      </AnimatedNativeView>
    </AnimatedNativeView>
  );
}, checkIfPropsAreSame);
