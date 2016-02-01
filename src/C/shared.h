/// IOStreamDescriptor structure
typedef struct IOStreamDescriptor {
  FILE * fd;

  char * result;
  char * lastMod;
  char * eTag;
  int contentLen;
  int len;
  int code;

} IOStreamDescriptor;

typedef struct IOParameters {
  const char *date_str;
  const char *signature;
  const char *resource_name;
  const char *resource_path;
  const char *bucket;
  IOStreamDescriptor *bf;
  int level;
  size_t (*callback)(void*, size_t, size_t, void*);
  void (*remote)(struct IOParameters params);
} IOParameters;

int mzx_copy_deflate_remote(IOParameters params);
