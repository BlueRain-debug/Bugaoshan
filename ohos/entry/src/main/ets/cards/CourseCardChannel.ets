import common from '@ohos.app.ability.common';
import formProvider from '@ohos.app.form.formProvider';
import { MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { CourseCardStore } from './CourseCardStore';

export class CourseCardChannel {
  private context: common.UIAbilityContext;
  private queue: Promise<void> = Promise.resolve();
  private disposed: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  handle(call: MethodCall, result: MethodResult): boolean {
    if (call.method !== 'updateWidget' && call.method !== 'openCourseFormManager') return false;
    this.queue = this.queue.then(async () => {
      try {
        if (this.disposed) throw new Error('Course card channel disposed');
        const store = new CourseCardStore(this.context.filesDir);
        if (call.method === 'updateWidget') {
          try {
            store.save(call.argument('snapshot') as string);
          } finally {
            await store.refreshAll();
          }
          result.success(null);
        } else {
          formProvider.openFormManager({
            bundleName: this.context.applicationInfo.name,
            abilityName: 'CourseFormAbility',
            parameters: {
              'ohos.extra.param.key.form_dimension': 3,
              'ohos.extra.param.key.form_name': 'CourseCard',
              'ohos.extra.param.key.module_name': 'entry'
            }
          });
          result.success(true); // Manager opened; the user still has to add the form.
        }
      } catch (error) {
        result.error('COURSE_CARD_FAILED', (error as Error).message, null);
      }
    });
    return true;
  }

  dispose(): void {
    this.disposed = true;
  }
}
