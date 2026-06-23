import type { FC, ReactNode } from 'react';
import { createContext, useState, useCallback, useEffect, useMemo, useContext } from 'react';
import { useUserPreference } from '@console/shared/src/hooks/useUserPreference';
import {
  applyPatternFlyThemeClasses,
  darkThemeMq,
  subscribeToPatternFlyThemeMediaQueries,
} from './patternflyTheme';

export {
  THEME_DARK_CLASS,
  THEME_FELT_CLASS,
  THEME_GLASS_CLASS,
  THEME_HIGH_CONTRAST_CLASS,
  darkThemeMq,
} from './patternflyTheme';

export const THEME_USER_PREFERENCE_KEY = 'console.theme';
export const THEME_LOCAL_STORAGE_KEY = 'bridge/theme';
const THEME_SYSTEM_DEFAULT = 'systemDefault';
export const THEME_DARK = 'dark';
export const THEME_LIGHT = 'light';

type PROCESSED_THEME = typeof THEME_DARK | typeof THEME_LIGHT;

type Theme = {
  theme: PROCESSED_THEME;
};

const resolveColorScheme = (theme: string): PROCESSED_THEME => {
  if (darkThemeMq.matches && theme === THEME_SYSTEM_DEFAULT) {
    theme = THEME_DARK;
  }
  return theme === THEME_DARK ? THEME_DARK : THEME_LIGHT;
};

export const ThemeContext = createContext<Theme>({
  theme: THEME_LIGHT,
});

interface ThemeProviderProps {
  children?: ReactNode;
}

/** Hook to determine the theme to apply, based on user preference and system settings. */
const useProcessedTheme = () => {
  const localTheme = localStorage.getItem(THEME_LOCAL_STORAGE_KEY) as PROCESSED_THEME;
  const [theme, , themeLoaded] = useUserPreference(
    THEME_USER_PREFERENCE_KEY,
    THEME_SYSTEM_DEFAULT,
    true,
  );
  const [processedTheme, setProcessedTheme] = useState<PROCESSED_THEME>(localTheme);

  const applyTheme = useCallback((themePreference: string) => {
    const colorScheme = resolveColorScheme(themePreference);
    applyPatternFlyThemeClasses(document.documentElement, colorScheme);
    setProcessedTheme(colorScheme);
  }, []);

  useEffect(() => {
    if (!themeLoaded) {
      return;
    }

    applyTheme(theme);

    if (theme === THEME_SYSTEM_DEFAULT) {
      const onSystemChange = () => applyTheme(THEME_SYSTEM_DEFAULT);
      darkThemeMq.addEventListener('change', onSystemChange);
      return () => darkThemeMq.removeEventListener('change', onSystemChange);
    }

    return undefined;
  }, [applyTheme, theme, themeLoaded]);

  useEffect(() => {
    if (!themeLoaded) {
      return;
    }

    const refreshContrastAndGlass = () => applyTheme(theme);
    return subscribeToPatternFlyThemeMediaQueries(refreshContrastAndGlass);
  }, [applyTheme, theme, themeLoaded]);

  useEffect(() => {
    if (themeLoaded) {
      localStorage.setItem(THEME_LOCAL_STORAGE_KEY, processedTheme);
    }
  }, [processedTheme, themeLoaded]);

  return processedTheme;
};

export const ThemeProvider: FC<ThemeProviderProps> = ({ children }) => {
  const processedTheme = useProcessedTheme();

  const providerValue = useMemo<Theme>(() => {
    return {
      theme: processedTheme,
    };
  }, [processedTheme]);

  return <ThemeContext.Provider value={providerValue}>{children}</ThemeContext.Provider>;
};

export const useTheme = () => useContext(ThemeContext);
