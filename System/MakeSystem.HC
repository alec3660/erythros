/* clang-format off */

DocMax(adam_task);
WinMax(adam_task);
WinToTop(adam_task);

#include "Setup/Environment";

// Erythros system drivers
"drivers: { ";
#include "Drivers/Audio";
#include "Drivers/Display";
#include "Drivers/Mouse";
#include "Drivers/Pci";
#include "Drivers/Virtio-blk";
#include "Drivers/VMSVGA";
#include "Drivers/VMwareTools";
#include "Drivers/AC97";
"}\n";

// FFI support files
#include "FFI/Base";
#include "FFI/LibC";
#include "FFI/New";
#include "FFI/ELF64";

// stb_image library
#include "Utilities/Image";
load_elf("M:/build/bin/image");

// stb_truetype library
#include "Utilities/TrueType";
load_elf("M:/build/bin/truetype");

// Jakt support files
#include "Jakt/OS";
#include "Jakt/IOPort";
#include "Jakt/PCI";
#include "Jakt/Time";

#include "Libraries/Tlse";
load_elf("M:/build/bin/tlse");

// Networking APIs
#include "Api/Dns.HC";
#include "Api/Icmp.HC";
#include "Api/Ipv4.HC";
#include "Api/MD5.HC";
#include "Api/NetInfo.HC";
#include "Api/Tcp.HC";
#include "Api/Tls.HC";

// Erythros system libraries
"libraries: { ";
#include "Libraries/Json";

// Load system-wide config values
JsonObject* config = Json.Parse(FileRead("M:/Settings/config.json"), erythros_mem_task);

#include "Libraries/Function";
#include "Libraries/Base64";
#include "Libraries/String";
#include "Libraries/BitmapFont";
#include "Libraries/Display";
#include "Libraries/FileSystem";
#include "Libraries/Graphics2D";
#include "Libraries/Animation2D";
#include "Libraries/Image";
#include "Libraries/Rsa";
#include "Libraries/Sha256";
#include "Libraries/System";
#include "Libraries/RawText";
#include "Libraries/User";
#include "Libraries/Session";
#include "Libraries/Shell";
#include "Libraries/Stdio";
#include "Libraries/Http";
#include "Libraries/Audio";
#include "Libraries/Gui";
#include "Libraries/Ipc";
#include "Libraries/Clipboard";
#include "Libraries/Widget";
#include "Libraries/Theme";


@http_init_tmp_and_cache_directories;

#include "Libraries/Css/Tokenizer";

#include "Libraries/Html/Tokenizer";
#include "Libraries/Html/Renderer";
"}\n";

load_elf("M:/build/bin/net");

// Networking Utilities
#include "Utilities/Dns";
#include "Utilities/NetRep";
#include "Utilities/Ping";
#include "Utilities/Time";

Spawn(_start, , "Net Task");

TimeSync;

#include "Core/Compositor";
#include "Core/FileSystem";
#include "Core/Menu";
#include "Core/MessageBox";
#include "Core/Shell";
#include "Core/ShellCommands";
#include "Core/SystemTray";
#include "Core/SystemStarter";

#include "Setup/Init";

/* clang-format on */
