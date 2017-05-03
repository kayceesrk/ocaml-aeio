#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/unixsupport.h>
#include <caml/bigarray.h>
#include <sys/uio.h>
#include <stdio.h>

static void fill_iovecs (struct iovec* iovecs, value iovec_array, int count)
{
  CAMLparam1 (iovec_array);
  CAMLlocal2 (iovec, ba);
  intnat i, offset, length;

  for (i = 0; i < count; i++) {
    caml_read_field (iovec_array, i, &iovec);
    caml_read_field (iovec, 0, &ba);
    offset = Long_field (iovec, 1);
    length = Long_field (iovec, 2);

    iovecs[i].iov_len = length;
    /* XXX KC: Not safe under multicore. iov_base is not a gc root. */
    iovecs[i].iov_base = &((char*)Caml_ba_data_val(ba))[offset];
  }

  CAMLreturn0;
}

CAMLprim value aeio_unix_bytes_writev (value fd, value iovec_array)
{
  CAMLparam2(fd, iovec_array);
  int count = caml_array_length (iovec_array);
  struct iovec iovecs[count];

  fill_iovecs(iovecs, iovec_array, count);

  ssize_t bytes_written = writev (Int_val(fd), iovecs, count);
  if (bytes_written == -1)
    uerror ("writev", Nothing);

  CAMLreturn(Val_long(bytes_written));
}
