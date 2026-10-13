/* Writes a marker, then calls a function missing from libmst.dylib (lazy in
 * the opcode encoding), so the marker shows whether guest code ran. */
extern long write(int, const void*, unsigned long);
extern int f_miss(void);

int main(void)
{
	write(1, "guest-ran\n", 10);
	return f_miss();
}
