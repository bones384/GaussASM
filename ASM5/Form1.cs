using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace ASM5
{
    public partial class Form1 : Form
    {
        Bitmap InputBitmap;
        public Form1()
        {
            InitializeComponent();
        }

        private void groupBox2_Enter(object sender, EventArgs e)
        {

        }

        private void pictureBox1_Click(object sender, EventArgs e)
        {

        }

        private void label4_Click(object sender, EventArgs e)
        {

        }

        private void label5_Click(object sender, EventArgs e)
        {

        }

        private void tableLayoutPanel2_Paint(object sender, PaintEventArgs e)
        {

        }

        private void label3_Click(object sender, EventArgs e)
        {

        }

        private void radioButton1_CheckedChanged(object sender, EventArgs e)
        {

        }

        private void radioButton3_CheckedChanged(object sender, EventArgs e)
        {

        }

        private void radioButton3_CheckedChanged_1(object sender, EventArgs e)
        {

        }

        private void label7_Click(object sender, EventArgs e)
        {

        }

        private void button1_Click(object sender, EventArgs e)
        {
            OpenFileDialog ofd = new OpenFileDialog();
            ofd.Filter = "Image Files|*.jpg;*.png;*.bmp;";

            if (ofd.ShowDialog() == DialogResult.OK)
            {
                InputBitmap = new Bitmap(ofd.FileName);
                pictureInput.Image = InputBitmap;
                LabelFile.Text = ofd.FileName;
            }

        }

        ushort[] generate_gaussian_kernel(float sigma, int kernel_radius)
        {
            ushort[] kernel_result = new ushort[kernel_radius];
            int[] kernel = new int[kernel_radius];
            float[] temp_kernel = new float[kernel_radius];
            float sum = 0;
            temp_kernel[0] = gaussian_distribution(0, sigma);
            sum += temp_kernel[0];
            for (int i = 1; i < kernel_radius; i++)
            {
                float v = gaussian_distribution(i, sigma);
                temp_kernel[i] = v;
                sum += 2 * v;
            }
            ushort fixedsum = 0;
            temp_kernel[0] /= sum;
            kernel_result[0] = (ushort)(temp_kernel[0] * (1 << 14));
            fixedsum += (ushort)kernel_result[0];
            for (int i = 1; i < kernel_radius; i++)
            {
                temp_kernel[i] /= sum;
                kernel_result[i] = (ushort)(temp_kernel[i] * (1 << 14));
                fixedsum += (ushort)(2 * kernel_result[i]);
            }
            kernel_result[0] += (ushort)((1 << 14) - fixedsum);
            return kernel_result;
        }
        private void InputKernel_ValueChanged(object sender, EventArgs e)
        {
            var nud = (NumericUpDown)sender;

            int value = (int)nud.Value;

        }
        float gaussian_distribution(int x, float sigma)
        {
            return (float)Math.Exp(-(x * x) / (2 * sigma * sigma));
        }
        [DllImport(@"C:\Users\mkowa\source\repos\ASM5\x64\Debug\gauss_cpp.dll")]
        static extern unsafe void gauss(byte* data, byte* temp,  int height, int width, int stride, ushort* kernel, int kernel_size, int start_row, int end_row, int isHorizontal);

        // [DllImport(@"C:\Users\mkowa\source\repos\ASM5\x64\Debug\gauss_cpp.dll")]
        [DllImport(@"C:\Users\mkowa\source\repos\ASM5\x64\Debug\asm.dll")]
        static extern unsafe void gauss_horizontal(byte* data, byte* temp,  int height, int width, int stride, ushort* kernel, int kernel_size, int start_row, int end_row);

        [DllImport(@"C:\Users\mkowa\source\repos\ASM5\x64\Debug\gauss_cpp.dll")]
        static extern unsafe void gauss_vertical(byte* data, byte* temp, int height, int width, int stride, ushort* kernel, int kernel_size, int start_row, int end_row);

        private void buttonCpp_Click(object sender, EventArgs e)
        {
            Cursor.Current = Cursors.WaitCursor;
            if (InputBitmap == null)
            {
                MessageBox.Show("Please load an image first.");
                return;
            }
            Stopwatch sw = new Stopwatch();
            sw.Start();

            Rectangle rect = new Rectangle(0, 0, InputBitmap.Width, InputBitmap.Height);


            BitmapData data = InputBitmap.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            byte[] image = new byte[data.Height * data.Stride];
            Marshal.Copy(data.Scan0, image, 0, image.Length);
            InputBitmap.UnlockBits(data);
            progressBar.Value = 0;

            int kernel_size = (int)InputKernel.Value;
            ushort[] kernel = generate_gaussian_kernel((float)InputSigma.Value, kernel_size);
            int thread_count = (int)InputThreads.Value;
            int slice_height = InputBitmap.Height / thread_count;
            Thread[] threads = new Thread[thread_count];
            progressBar.Maximum = 2 * thread_count + 1;

            byte[] temp = new byte[InputBitmap.Height * data.Stride];


            unsafe
            {
                ushort* p_kernel;
                byte* p_temp, p_image;
                fixed (ushort* fixed_kernel = kernel)
                fixed (byte* fixed_image = image)

                {
                    fixed (byte* fixed_temp = temp)
                    {
                        p_temp = fixed_temp;
                        p_kernel = fixed_kernel;
                        p_image = fixed_image;
                        for (int i = 0; i < thread_count; i++)
                        {
                            int start_row = i * slice_height;
                            int end_row = (i == thread_count - 1) ? InputBitmap.Height : start_row + slice_height;
                            threads[i] = new Thread(() =>
                            {
                                gauss_horizontal(p_image, p_temp, InputBitmap.Height, InputBitmap.Width, data.Stride, p_kernel, kernel_size, start_row, end_row);
                            });
                            threads[i].Start();

                        }


                        for (int i = 0; i < thread_count; i++)
                        {
                            threads[i].Join();
                            progressBar.Value += 2;
                            progressBar.Value -= 1;




                        }

                        for (int i = 0; i < thread_count; i++)
                        {
                            int start_row = i * slice_height;
                            int end_row = (i == thread_count - 1) ? InputBitmap.Height : start_row + slice_height;
                            threads[i] = new Thread(() =>
                            {

                                gauss_vertical(p_image, p_temp, InputBitmap.Height, InputBitmap.Width, data.Stride, p_kernel, kernel_size, start_row, end_row);
                            });
                            threads[i].Start();
                        }

                        for (int i = 0; i < thread_count; i++)
                        {
                            threads[i].Join();
                            progressBar.Value += 2;
                            progressBar.Value -= 1;
                        }

                        progressBar.Maximum = 2 * thread_count;
                    }
                }
            }

            Bitmap output = new Bitmap(InputBitmap.Width, InputBitmap.Height, PixelFormat.Format32bppArgb);

            data = output.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            Marshal.Copy(image, 0, data.Scan0, image.Length);
            output.UnlockBits(data);
            if (pictureOutput.Image != null)
            {
                var old = pictureOutput.Image;
                pictureOutput.Image = null;
                old.Dispose();
            }
            pictureOutput.Image = output;
            sw.Stop();
            Console.WriteLine("Elapsed={0}", sw.Elapsed);
            Cursor.Current = Cursors.Arrow;

        }

        private void label6_Click(object sender, EventArgs e)
        {

        }

        private void label9_Click(object sender, EventArgs e)
        {

        }

        private void label8_Click(object sender, EventArgs e)
        {

        }
    }
}
