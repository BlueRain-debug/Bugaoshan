import {
  FlutterAbility,
  FlutterEngine,
  MethodCall,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import Want from '@ohos.app.ability.Want';
import wantConstant from '@ohos.app.ability.wantConstant';
import fileuri from '@ohos.file.fileuri';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { DynamicIconChannel } from '../platform/DynamicIconChannel';
import { EnvironmentInfoChannel } from '../platform/EnvironmentInfoChannel';
import { CourseCardChannel } from '../cards/CourseCardChannel';

const CHANNEL = 'bugaoshan/update';

export default class EntryAbility extends FlutterAbility {
  private methodChannel: MethodChannel | null = null;
  private iconChannel: MethodChannel | null = null;
  private environmentChannel: MethodChannel | null = null;
  private cards: CourseCardChannel | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);

    const icons = new DynamicIconChannel();
    this.iconChannel = new MethodChannel(flutterEngine.getDartExecutor(), 'bugaoshan/dynamic_icon');
    this.iconChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        icons.handle(call, result);
      }
    });
    const environment = new EnvironmentInfoChannel();
    this.environmentChannel = new MethodChannel(flutterEngine.getDartExecutor(), 'bugaoshan/environment_info');
    this.environmentChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        environment.handle(call, result);
      }
    });
    this.cards = new CourseCardChannel(this.context);
    this.methodChannel = new MethodChannel(flutterEngine.getDartExecutor(), CHANNEL);
    this.methodChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method === 'importIcsToCalendar') {
          this.importIcsToCalendar(call.argument('path') as string, result);
        } else if (this.cards?.handle(call, result)) {
          // The card handler completes its own result.
        } else {
          result.notImplemented();
        }
      }
    });
  }

  cleanUpFlutterEngine(flutterEngine: FlutterEngine): void {
    this.cards?.dispose();
    this.methodChannel?.setMethodCallHandler(null);
    this.iconChannel?.setMethodCallHandler(null);
    this.environmentChannel?.setMethodCallHandler(null);
    this.methodChannel = null;
    this.iconChannel = null;
    this.environmentChannel = null;
    this.cards = null;
    super.cleanUpFlutterEngine(flutterEngine);
  }

  private async importIcsToCalendar(path: string, result: MethodResult): Promise<void> {
    if (typeof path !== 'string' || path.length === 0) {
      result.error('INVALID_ARGUMENT', 'Path is empty', null);
      return;
    }

    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: fileuri.getUriFromPath(path),
        type: 'text/calendar',
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
        parameters: {
          mimeType: 'text/calendar'
        }
      };

      await this.context.startAbility(want);
      // 这里只确认打开了接收端，实际导入由用户在日历应用中确认。
      result.success('opened');
    } catch (error) {
      result.error('OPEN_FAILED', (error as Error).message, null);
    }
  }
}
