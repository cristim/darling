/* X11 does not provide the macOS secure-event or TSM document facilities.
 * Export the entry points and report unsupported instead of aborting in dyld.
 * Do not claim that ordinary X11 keyboard input has become secure. */
int EnableSecureEventInput(void) { return -4; }
int DisableSecureEventInput(void) { return -4; }
int TSMSetDocumentProperty(void *document, unsigned tag, unsigned size,
                          void *data) {
    (void)document; (void)tag; (void)size; (void)data;
    return -4;
}
int TSMRemoveDocumentProperty(void *document, unsigned tag) {
    (void)document; (void)tag;
    return -4;
}
