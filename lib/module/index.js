import DocumentScanner from './NativeDocumentScanner.js';
export { ResponseType, ScanDocumentResponseStatus } from './NativeDocumentScanner.js';
export default {
  /**
   * Opens the camera, and starts the document scan
   */
  scanDocument(options = {}) {
    return DocumentScanner.scanDocument(options);
  },
};
