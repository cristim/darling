extern int d_data;
extern int f_weak(void) __attribute__((weak_import));

int main(void)
{
	return d_data + (f_weak ? 9 : 0);
}
