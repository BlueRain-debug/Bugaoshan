import fs from '@ohos.file.fs';
import util from '@ohos.util';
import i18n from '@ohos.i18n';
import hilog from '@ohos.hilog';
import formBindingData from '@ohos.app.form.formBindingData';
import formProvider from '@ohos.app.form.formProvider';
import { CardBinding, CourseSnapshot, decodeSnapshot, makeCardView, nextRefreshMinutes } from './CourseCardModel';

const MAX_SNAPSHOT_BYTES = 2 * 1024 * 1024;

export class CourseCardStore {
  private directory: string;
  private snapshotPath: string;

  constructor(filesDir: string) {
    this.directory = `${filesDir}/course_cards`;
    this.snapshotPath = `${this.directory}/snapshot-v1.json`;
    if (!fs.accessSync(this.directory)) {
      try {
        fs.mkdirSync(this.directory, true);
      } catch (error) {
        // The UIAbility and extension may create their shared directory together.
        if (!fs.accessSync(this.directory) || !fs.statSync(this.directory).isDirectory()) {
          throw new Error((error as Error).message);
        }
      }
    }
  }

  private writeAtomic(path: string, text: string): void {
    const temporary = `${path}.${util.generateRandomUUID()}.tmp`;
    const bytes = new util.TextEncoder().encodeInto(text);
    try {
      const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        let offset = 0;
        while (offset < bytes.length) {
          const written = fs.writeSync(file.fd, bytes.slice(offset).buffer);
          if (written <= 0) throw new Error('Could not write course snapshot');
          offset += written;
        }
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }
      fs.renameSync(temporary, path);
    } finally {
      if (fs.accessSync(temporary)) fs.unlinkSync(temporary);
    }
  }

  save(json: string): void {
    try {
      if (typeof json !== 'string' || new util.TextEncoder().encodeInto(json).length > MAX_SNAPSHOT_BYTES) {
        throw new Error('Course snapshot exceeds size limit');
      }
      const snapshot = decodeSnapshot(json);
      this.writeAtomic(this.snapshotPath, JSON.stringify(snapshot));
    } catch (error) {
      // A bad new snapshot must not leave another schedule visible indefinitely.
      this.writeAtomic(this.snapshotPath, JSON.stringify(new CourseSnapshot()));
      throw new Error((error as Error).message);
    }
  }

  load(): CourseSnapshot {
    try {
      if (!fs.accessSync(this.snapshotPath)) return new CourseSnapshot();
      if (fs.statSync(this.snapshotPath).size > MAX_SNAPSHOT_BYTES) throw new Error('Snapshot too large');
      return decodeSnapshot(fs.readTextSync(this.snapshotPath));
    } catch (error) {
      hilog.warn(0x0000, 'CourseCard', 'Cannot read snapshot: %{public}s', (error as Error).message);
      return new CourseSnapshot();
    }
  }

  bindingData(): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(
      new CardBinding(makeCardView(this.load(), i18n.System.getSystemLanguage())));
  }

  private validId(id: string): boolean {
    return typeof id === 'string' && /^\d{1,20}$/.test(id) && id !== '0';
  }

  remember(id: string): void {
    if (!this.validId(id)) return;
    // One file per instance: the UI and FormExtension processes never rewrite a shared index.
    const file = fs.openSync(`${this.directory}/${id}.form`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
    fs.closeSync(file);
  }

  forget(id: string): void {
    if (!this.validId(id)) return;
    const path = `${this.directory}/${id}.form`;
    if (fs.accessSync(path)) fs.unlinkSync(path);
  }

  async refresh(id: string): Promise<void> {
    if (!this.validId(id) || !fs.accessSync(`${this.directory}/${id}.form`)) return;
    await formProvider.updateForm(id, this.bindingData());
    await this.scheduleNext(id);
  }

  async scheduleNext(id: string): Promise<void> {
    if (!this.validId(id) || !fs.accessSync(`${this.directory}/${id}.form`)) return;
    try {
      const delay = nextRefreshMinutes(this.load());
      // Regular 30-minute updates already cover the other cases.
      if (delay < 30) await formProvider.setFormNextRefreshTime(id, delay);
    } catch (error) {
      hilog.warn(0x0000, 'CourseCard', 'Refresh scheduling unavailable: %{public}s', (error as Error).message);
    }
  }

  async refreshAll(): Promise<void> {
    const entries = fs.listFileSync(this.directory);
    for (const entry of entries) {
      if (!/^\d{1,20}\.form$/.test(entry)) continue;
      try {
        await this.refresh(entry.substring(0, entry.length - 5));
      } catch (error) {
        // A removed/unavailable instance cannot prevent the other instances updating.
        hilog.warn(0x0000, 'CourseCard', 'Instance update failed: %{public}s', (error as Error).message);
      }
    }
  }
}
