import type { IconData, IconDefinition } from '@patternfly/react-icons/dist/esm/createIcon';

const ICON_OPERATOR = 'icon-operator';
export type CSVIcon = { base64data: string; mediatype: string };
export const getImageForCSVIcon = (icon: CSVIcon | undefined) => {
  return icon ? `data:${icon.mediatype};base64,${icon.base64data}` : ICON_OPERATOR;
};

export const getDefaultOperatorIcon = () => ICON_OPERATOR;

type PfIconConfigInput =
  | IconDefinition
  | {
      icon?: IconData | null;
    };

const getIconData = (iconConfig: PfIconConfigInput): IconData | IconDefinition => {
  if ('icon' in iconConfig && iconConfig.icon) {
    return iconConfig.icon;
  }
  return iconConfig as IconDefinition;
};

const getSvgPathsMarkup = (svgPath: string | IconData['svgPathData']): string => {
  if (!svgPath) {
    return '';
  }
  if (Array.isArray(svgPath)) {
    return svgPath
      .map((pathObject) => `<path class="${pathObject.className || ''}" d="${pathObject.path}" />`)
      .join('');
  }
  return `<path d="${svgPath}" />`;
};

/**
 * Modified from PF createIcon, returns a string with the SVG element instead of a React component.
 */
export const getSvgFromPfIconConfig = (
  iconConfig: PfIconConfigInput,
  className?: string,
): string => {
  const iconData = getIconData(iconConfig);
  const xOffset = iconData.xOffset ?? 0;
  const yOffset = iconData.yOffset ?? 0;
  const { width, height } = iconData;
  const viewBox = [xOffset, yOffset, width, height].join(' ');
  const svgPath =
    'svgPathData' in iconData && iconData.svgPathData
      ? iconData.svgPathData
      : (iconData as IconDefinition).svgPath;

  return `
<svg className="pf-v6-svg ${className || ''}"
  viewBox='${viewBox}'
  fill="currentColor"
  role="img"
  width="1em"
  height="1em"
>
    ${getSvgPathsMarkup(svgPath)}
</svg>`;
};
