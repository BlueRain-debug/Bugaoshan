import path from 'path'
import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { flutterHvigorPlugin } from 'flutter-hvigor-plugin';
import { flutterEmbeddingPlugin } from './tool/flutter_embedding_plugin';

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins: [
        flutterHvigorPlugin(path.dirname(__dirname)),
        flutterEmbeddingPlugin(__dirname),
    ]
}
