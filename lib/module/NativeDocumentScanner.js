import { TurboModuleRegistry } from 'react-native';
export let ResponseType = /*#__PURE__*/ (function (ResponseType) {
  ResponseType['Base64'] = 'base64';
  ResponseType['ImageFilePath'] = 'imageFilePath';
  return ResponseType;
})({});
export let ScanDocumentResponseStatus = /*#__PURE__*/ (function (
  ScanDocumentResponseStatus
) {
  ScanDocumentResponseStatus['Success'] = 'success';
  ScanDocumentResponseStatus['Cancel'] = 'cancel';
  return ScanDocumentResponseStatus;
})({});
export default TurboModuleRegistry.getEnforcing('DocumentScanner');
