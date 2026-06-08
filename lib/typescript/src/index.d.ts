import { type ScanDocumentOptions, type ScanDocumentResponse } from './NativeDocumentScanner';
export type { ScanDocumentOptions, ScanDocumentResponse, } from './NativeDocumentScanner';
export { ResponseType, ScanDocumentResponseStatus, } from './NativeDocumentScanner';
declare const _default: {
    /**
     * Opens the camera, and starts the document scan
     */
    scanDocument(options?: ScanDocumentOptions): Promise<ScanDocumentResponse>;
};
export default _default;
