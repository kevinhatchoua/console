/**
 * PatternFly v6 theme class management.
 * @see https://www.patternfly.org/foundations-and-styles/theming/glass-mode-handbook
 * @see https://www.patternfly.org/foundations-and-styles/theming/theming
 */

export const THEME_DARK_CLASS = 'pf-v6-theme-dark';
export const THEME_GLASS_CLASS = 'pf-v6-theme-glass';
export const THEME_FELT_CLASS = 'pf-v6-theme-felt';
export const THEME_HIGH_CONTRAST_CLASS = 'pf-v6-theme-high-contrast';

export const darkThemeMq = window.matchMedia('(prefers-color-scheme: dark)');
export const reducedTransparencyMq = window.matchMedia('(prefers-reduced-transparency: reduce)');
export const forcedColorsMq = window.matchMedia('(forced-colors: active)');
export const prefersContrastMq = window.matchMedia('(prefers-contrast: more)');

/** High contrast takes precedence over glass per the glass mode handbook. */
export const shouldUseHighContrast = (): boolean =>
  forcedColorsMq.matches || prefersContrastMq.matches;

/** Glass is disabled when high contrast or reduced transparency is requested. */
export const shouldEnableGlassMode = (): boolean =>
  !reducedTransparencyMq.matches && !shouldUseHighContrast();

export type PatternFlyColorScheme = 'dark' | 'light';

export const applyPatternFlyThemeClasses = (
  html: HTMLElement,
  colorScheme: PatternFlyColorScheme,
): void => {
  html.classList.toggle(THEME_DARK_CLASS, colorScheme === 'dark');
  html.classList.add(THEME_FELT_CLASS);

  const glassEnabled = shouldEnableGlassMode();
  html.classList.toggle(THEME_GLASS_CLASS, glassEnabled);
  html.classList.toggle(THEME_HIGH_CONTRAST_CLASS, shouldUseHighContrast() && !glassEnabled);
};

export const subscribeToPatternFlyThemeMediaQueries = (listener: () => void): (() => void) => {
  const mediaQueries = [darkThemeMq, reducedTransparencyMq, forcedColorsMq, prefersContrastMq];
  mediaQueries.forEach((mq) => mq.addEventListener('change', listener));
  return () => mediaQueries.forEach((mq) => mq.removeEventListener('change', listener));
};
