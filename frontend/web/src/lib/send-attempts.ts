interface SendAttempt {
  clientId: string;
  content: string;
  files: readonly File[];
}

// Remembers only the current session's manual attempts. This never sends or
// persists messages; a click on Send is always required.
export class SendAttempts {
  private attempts = new Map<string, SendAttempt>();

  get(conversationId: string, content: string, files: readonly File[]): string {
    const previous = this.attempts.get(conversationId);
    if (
      previous?.content === content &&
      previous.files.length === files.length &&
      previous.files.every((file, index) => file === files[index])
    )
      return previous.clientId;
    const clientId = crypto.randomUUID();
    this.attempts.set(conversationId, { clientId, content, files: [...files] });
    return clientId;
  }

  clear(conversationId: string) {
    this.attempts.delete(conversationId);
  }
}
