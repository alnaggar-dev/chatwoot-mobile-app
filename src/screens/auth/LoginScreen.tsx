import React, { useEffect, useState } from 'react';
import { Controller, useForm } from 'react-hook-form';
import { Animated, Image, Pressable, StatusBar, TextInput, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import {
  BottomSheetModal,
  BottomSheetScrollView,
  useBottomSheetSpringConfigs,
} from '@gorhom/bottom-sheet';
import { SafeAreaView } from 'react-native-safe-area-context';
import { KeyboardAwareScrollView } from 'react-native-keyboard-controller';

import { EMAIL_REGEX } from '@/constants';
import { EyeIcon, EyeSlash, LockIcon, TranslateIcon } from '@/svg-icons';
import { tailwind } from '@/theme';
import i18n from '@/i18n';
import { resetAuth } from '@/store/auth/authSlice';
import { authActions } from '@/store/auth/authActions';
import { useAppDispatch, useAppSelector } from '@/hooks';

import {
  BottomSheetBackdrop,
  BottomSheetHeader,
  LanguageList,
  Button,
  Icon,
  AuthButton,
} from '@/components-next';
import { selectInstallationUrl, selectLocale } from '@/store/settings/settingsSelectors';
import { selectIsLoggingIn } from '@/store/auth/authSelectors';
import { setLocale } from '@/store/settings/settingsSlice';
import { useRefsContext } from '@/context/RefsContext';
import { SsoUtils } from '@/utils/ssoUtils';

type FormData = {
  email: string;
  password: string;
};

const LoginScreen = () => {
  const navigation = useNavigation();
  const [showPassword, setShowPassword] = useState(false);
  const [focusedField, setFocusedField] = useState<'email' | 'password' | null>(null);
  const {
    control,
    handleSubmit,
    formState: { errors },
  } = useForm<FormData>({
    defaultValues: {
      email: '',
      password: '',
    },
  });

  const { languagesModalSheetRef } = useRefsContext();

  const animationConfigs = useBottomSheetSpringConfigs({
    mass: 1,
    stiffness: 420,
    damping: 30,
  });

  const dispatch = useAppDispatch();
  const isLoggingIn = useAppSelector(selectIsLoggingIn);

  const installationUrl = useAppSelector(selectInstallationUrl);
  const activeLocale = useAppSelector(selectLocale);

  useEffect(() => {
    languagesModalSheetRef.current?.dismiss({
      overshootClamping: true,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeLocale]);

  useEffect(() => {
    dispatch(resetAuth());
  }, [dispatch]);

  const onSubmit = async (data: FormData) => {
    const { email, password } = data;
    // Clear any existing auth state before login
    dispatch(resetAuth());

    try {
      const result = await dispatch(authActions.login({ email, password })).unwrap();

      // Check if MFA is required in the response
      if ('mfa_required' in result && result.mfa_required) {
        // Navigate directly to MFA screen with the token
        navigation.navigate('MFAScreen' as never);
      }
      // If MFA not required, the auth state will be updated and
      // the app will automatically navigate to the dashboard
    } catch {
      // Login error is handled by Redux and displayed in the UI
    }
  };

  // TODO: Change this condition based on EE check
  // Show SSO login button only if installation URL contains app.foxdeskai.com
  const showSsoLogin = installationUrl.includes('app.foxdeskai.com');

  const openResetPassword = () => {
    navigation.navigate('ResetPassword' as never);
  };

  const onChangeLanguage = (locale: string) => {
    dispatch(setLocale(locale));
  };

  const handleSsoLogin = async () => {
    if (!installationUrl) {
      return;
    }

    try {
      const result = await SsoUtils.loginWithSSO(installationUrl);

      if (result.type === 'success' && result.url) {
        const ssoParams = SsoUtils.parseCallbackUrl(result.url);
        await SsoUtils.handleSsoCallback(ssoParams, dispatch);
      }
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
    } catch (error) {
      // SSO login error handled silently
    }
  };

  return (
    <SafeAreaView edges={['top', 'bottom']} style={tailwind.style('flex-1 bg-white')}>
      <StatusBar
        translucent
        backgroundColor={tailwind.color('bg-white')}
        barStyle={'dark-content'}
      />
      <KeyboardAwareScrollView
        style={tailwind.style('flex-1')}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
        bottomOffset={24}
        contentContainerStyle={tailwind.style('px-6 pt-16 pb-8')}>
        <View style={tailwind.style('relative flex-row items-center justify-center')}>
          <Image
            // eslint-disable-next-line @typescript-eslint/no-var-requires, @typescript-eslint/no-require-imports
            source={require('@/assets/images/logo.png')}
            style={tailwind.style('w-20 h-20')}
            resizeMode="contain"
          />
          <Pressable
            hitSlop={8}
            accessibilityRole="button"
            accessibilityLabel={i18n.t('LOGIN.CHANGE_LANGUAGE')}
            style={({ pressed }) =>
              tailwind.style(
                'absolute right-0 top-[18px] h-11 w-11 items-center justify-center rounded-full border border-outline',
                pressed ? 'bg-surface-subtle' : '',
              )
            }
            onPress={() => languagesModalSheetRef.current?.present()}>
            <Icon
              size={20}
              icon={<TranslateIcon stroke={tailwind.color('text-ink-secondary')} />}
            />
          </Pressable>
        </View>
        <Animated.Text
          style={tailwind.style(
            'pt-6 text-2xl leading-8 text-ink font-inter-semibold-20 text-center',
          )}>
          {i18n.t('LOGIN.TITLE')}
        </Animated.Text>

        <Controller
          control={control}
          rules={{
            required: i18n.t('LOGIN.EMAIL_REQUIRED'),
            pattern: {
              value: EMAIL_REGEX,
              message: i18n.t('LOGIN.EMAIL_ERROR'),
            },
          }}
          render={({ field: { onChange, onBlur, value } }) => (
            <View style={tailwind.style('pt-10 gap-2')}>
              <Animated.Text style={tailwind.style('font-inter-420-20 text-ink')}>
                {i18n.t('LOGIN.EMAIL')}
              </Animated.Text>
              <TextInput
                style={tailwind.style(
                  'text-base font-inter-normal-20 tracking-[0.24px] leading-[20px] android:leading-[18px]',
                  'h-12 px-4 rounded-control bg-white border text-ink',
                  errors.email
                    ? 'border-ruby-700'
                    : focusedField === 'email'
                      ? 'border-brand'
                      : 'border-outline',
                )}
                onFocus={() => setFocusedField('email')}
                onBlur={() => {
                  setFocusedField(null);
                  onBlur();
                }}
                onChangeText={onChange}
                value={value}
                placeholderTextColor={tailwind.color('text-ink-muted')}
                keyboardType="email-address"
                autoCapitalize="none"
              />
              {errors.email && (
                <Animated.Text style={tailwind.style('font-inter-normal-20 text-ruby-900')}>
                  {errors.email.message}
                </Animated.Text>
              )}
            </View>
          )}
          name="email"
        />

        <Controller
          control={control}
          rules={{
            required: i18n.t('LOGIN.PASSWORD_REQUIRED'),
            minLength: {
              value: 6,
              message: i18n.t('LOGIN.PASSWORD_ERROR'),
            },
          }}
          render={({ field: { onChange, onBlur, value } }) => (
            <View style={tailwind.style('pt-6 gap-2')}>
              <View style={tailwind.style('flex-row items-center justify-between')}>
                <Animated.Text style={tailwind.style('font-inter-420-20 text-ink')}>
                  {i18n.t('LOGIN.PASSWORD')}
                </Animated.Text>
                <Pressable
                  style={tailwind.style('flex-1 ml-4')}
                  hitSlop={8}
                  onPress={openResetPassword}>
                  <Animated.Text
                    style={tailwind.style('text-sm font-inter-medium-24 text-brand text-right')}>
                    {i18n.t('LOGIN.FORGOT_PASSWORD')}
                  </Animated.Text>
                </Pressable>
              </View>
              <View style={tailwind.style('relative')}>
                <TextInput
                  style={tailwind.style(
                    'text-base font-inter-normal-20 tracking-[0.24px] leading-[20px] android:leading-[18px]',
                    'h-12 pl-4 pr-12 rounded-control bg-white border text-ink',
                    errors.password
                      ? 'border-ruby-700'
                      : focusedField === 'password'
                        ? 'border-brand'
                        : 'border-outline',
                  )}
                  onFocus={() => setFocusedField('password')}
                  onBlur={() => {
                    setFocusedField(null);
                    onBlur();
                  }}
                  onChangeText={onChange}
                  value={value}
                  placeholderTextColor={tailwind.color('text-ink-muted')}
                  secureTextEntry={!showPassword}
                />
                <Pressable
                  hitSlop={8}
                  style={tailwind.style('absolute right-4 top-3.5')}
                  onPress={() => setShowPassword(!showPassword)}>
                  <Icon size={20} icon={showPassword ? <EyeIcon /> : <EyeSlash />} />
                </Pressable>
              </View>
              {errors.password && (
                <Animated.Text style={tailwind.style('font-inter-normal-20 text-ruby-900')}>
                  {errors.password.message}
                </Animated.Text>
              )}
            </View>
          )}
          name="password"
        />

        <View style={tailwind.style('pt-8')}>
          <Button
            text={isLoggingIn ? i18n.t('LOGIN.LOGIN_LOADING') : i18n.t('LOGIN.LOGIN')}
            handlePress={handleSubmit(onSubmit)}
            disabled={isLoggingIn}
          />
        </View>

        {showSsoLogin && (
          <View>
            <View style={tailwind.style('flex-row items-center my-6')}>
              <View style={tailwind.style('flex-1 h-px bg-outline')} />
              <Animated.Text style={tailwind.style('px-3 text-sm text-ink-muted')}>
                {i18n.t('LOGIN.OR')}
              </Animated.Text>
              <View style={tailwind.style('flex-1 h-px bg-outline')} />
            </View>
            <AuthButton
              text={i18n.t('LOGIN.LOGIN_VIA_SSO')}
              icon={<LockIcon />}
              handlePress={handleSsoLogin}
              disabled={isLoggingIn}
              variant="outline"
            />
          </View>
        )}
      </KeyboardAwareScrollView>
      <BottomSheetModal
        ref={languagesModalSheetRef}
        backdropComponent={BottomSheetBackdrop}
        handleIndicatorStyle={tailwind.style('overflow-hidden bg-blackA-A6 w-8 h-1 rounded-[11px]')}
        detached
        enablePanDownToClose
        animationConfigs={animationConfigs}
        handleStyle={tailwind.style('p-0 h-4 pt-[5px]')}
        style={tailwind.style('rounded-[26px] overflow-hidden')}
        snapPoints={['70%']}>
        <BottomSheetScrollView showsVerticalScrollIndicator={false}>
          <BottomSheetHeader headerText={i18n.t('SETTINGS.SET_LANGUAGE')} />
          <LanguageList onChangeLanguage={onChangeLanguage} currentLanguage={activeLocale} />
        </BottomSheetScrollView>
      </BottomSheetModal>
    </SafeAreaView>
  );
};

export default LoginScreen;
