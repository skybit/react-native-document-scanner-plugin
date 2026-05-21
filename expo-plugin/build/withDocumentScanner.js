'use strict';
Object.defineProperty(exports, '__esModule', { value: true });
const config_plugins_1 = require('@expo/config-plugins');
const pkg = require('react-native-document-scanner-plugin/package.json');
const CAMERA_USAGE = 'Allow $(PRODUCT_NAME) to access your camera';
const withDocumentScanner = (config, { cameraPermission } = {}) => {
  config = (0, config_plugins_1.withInfoPlist)(config, (nextConfig) => {
    nextConfig.modResults.NSCameraUsageDescription =
      cameraPermission ||
      nextConfig.modResults.NSCameraUsageDescription ||
      CAMERA_USAGE;
    return nextConfig;
  });
  return config;
};
exports.default = (0, config_plugins_1.createRunOncePlugin)(
  withDocumentScanner,
  pkg.name,
  pkg.version
);
